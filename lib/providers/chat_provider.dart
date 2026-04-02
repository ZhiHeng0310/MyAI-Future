import 'package:flutter/material.dart';
import '../models/checkin_model.dart';
import '../models/patient_model.dart';
import '../models/appointment_model.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'queue_provider.dart';

class ChatMessage {
  final String       text;
  final bool         isUser;
  final String?      risk;
  final List<String> actions;
  final bool         showBookingPrompt;
  final DateTime     timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions          = const [],
    this.showBookingPrompt = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatProvider extends ChangeNotifier {
  GeminiService  _gemini    = GeminiService(role: GeminiRole.patient);
  final _db                 = FirestoreService();
  QueueProvider? _queueProvider;

  final List<ChatMessage> _messages = [];
  bool           _thinking      = false;
  bool           _sessionReady  = false;
  String?        _todayQuestion;
  PatientModel?  _patient;

  List<ChatMessage> get messages      => _messages;
  bool              get thinking      => _thinking;
  bool              get sessionReady  => _sessionReady;
  String?           get todayQuestion => _todayQuestion;

  void setQueueProvider(QueueProvider qp) => _queueProvider = qp;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;
    if (patient.diagnosis != null) {
      await _gemini.initSession(
        name: patient.name, diagnosis: patient.diagnosis!,
        daysSinceVisit: patient.daysSinceVisit, medications: [],
      );
      _todayQuestion = await _gemini.generateCheckInQuestion(
          patient.diagnosis!, patient.daysSinceVisit);
    }
    _sessionReady = true;
    _messages.add(ChatMessage(
      text: 'Hi ${patient.name.split(' ').first}! 👋 I\'m CareLoop AI. '
          '${_todayQuestion ?? "How are you feeling today?"}\n\n'
          'I can help with your recovery, medications, or book an appointment. Just ask!',
      isUser: false,
    ));
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  Future<void> resetSession(PatientModel? patient) async {
    _messages.clear();
    _sessionReady  = false;
    _todayQuestion = null;
    _gemini        = GeminiService(role: GeminiRole.patient);
    notifyListeners();
    if (patient != null) await initSession(patient);
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(ChatMessage(text: text, isUser: true));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessage(text);

    String displayMsg     = response.message;
    List<String> finalAct = List.from(response.actions);
    bool showBooking      = false;

    // ── Agentic: join queue ────────────────────────────────────────────────
    if (response.actions.contains('join_queue')) {
      displayMsg = await _handleQueueJoin(response);
      finalAct.remove('join_queue');
    }

    // ── Agentic: appointment booking intent ────────────────────────────────
    if (response.actions.contains('book_appointment') ||
        response.appointmentIntent) {
      showBooking = true;
      finalAct.remove('book_appointment');
    }

    // ── Agentic: health alert ─────────────────────────────────────────────
    if (response.actions.contains('alert_doctor') && _patient != null) {
      await _triggerHealthAlert(
        message:   text,
        riskLevel: response.risk.name,
      );
    }

    _messages.add(ChatMessage(
      text:              displayMsg,
      isUser:            false,
      risk:              response.risk.name,
      actions:           finalAct,
      showBookingPrompt: showBooking,
    ));
    _thinking = false;
    notifyListeners();

    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id:               '',
        patientId:        _patient!.id,
        userMessage:      text,
        aiResponse:       displayMsg,
        risk:             response.risk.name,
        actionsTriggered: finalAct,
        createdAt:        DateTime.now(),
      ));
      for (final a in finalAct) await _handleAction(a, displayMsg);
    }
  }

  // ── Health alert ──────────────────────────────────────────────────────────
  Future<void> _triggerHealthAlert({
    required String message,
    required String riskLevel,
  }) async {
    if (_patient == null) return;
    final doctorId = _patient!.assignedDoctorId;
    if (doctorId == null || doctorId.isEmpty) return;

    // Get patient name for alert
    final alert = HealthAlert(
      id:          '',
      patientId:   _patient!.id,
      patientName: _patient!.name,
      doctorId:    doctorId,
      message:     message,
      riskLevel:   riskLevel,
      status:      'pending',
      createdAt:   DateTime.now(),
    );
    await _db.createHealthAlert(alert);

    // Local notification for doctor (if on same device — dev testing)
    await NotificationService.showHealthAlert(
        '${_patient!.name} reported: $message');
  }

  // ── Queue auto-join ───────────────────────────────────────────────────────
  Future<String> _handleQueueJoin(GeminiResponse r) async {
    if (_queueProvider == null || _patient == null) {
      return 'I\'d love to help you join the queue. '
          'Please use the Queue tab to register.';
    }
    if (_queueProvider!.isAlreadyInQueue) {
      final pos  = _queueProvider!.myPosition;
      final wait = _queueProvider!.myEstimatedWait;
      return 'You\'re already in the queue at position #$pos. '
          '${wait == 0 ? "You\'re next!" : "~$wait minutes estimated wait."} 🏥';
    }
    final symptoms = r.queueSymptoms.isNotEmpty
        ? r.queueSymptoms : ['General consultation'];
    await _queueProvider!.joinQueue(
      patientId:   _patient!.id,
      patientName: _patient!.name,
      symptoms:    symptoms,
    );
    await Future.delayed(const Duration(milliseconds: 600));
    final pos  = _queueProvider!.myPosition;
    final wait = _queueProvider!.myEstimatedWait;
    return '✅ Done! I\'ve added you to the queue. You are #$pos. '
        '${pos <= 1 ? "You\'re next — head to the clinic!" : "~$wait minutes estimated wait."} 🏥';
  }

  // ── Other actions ─────────────────────────────────────────────────────────
  Future<void> _handleAction(String action, String context) async {
    if (_patient == null) return;
    switch (action) {
      case 'suggest_revisit':
        await _db.createAlert(
          patientId: _patient!.id, type: 'revisit',
          message:   'AI recommends revisit: $context',
        );
        break;
      case 'remind_medication':
        await NotificationService.showImmediateReminder(
            'CareLoop: please take your medication as prescribed.');
        break;
      case 'increase_priority':
        _queueProvider?.escalatePriority();
        break;
    }
  }

  void clearChat() {
    _messages.clear();
    _sessionReady = false;
    _gemini       = GeminiService(role: GeminiRole.patient);
    notifyListeners();
  }
}