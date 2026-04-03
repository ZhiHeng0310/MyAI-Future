import 'dart:typed_data';
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
  final bool         hasImage;

  /// ✅ FIX 1: Store appointment symptoms from Gemini so booking screen
  /// receives actual medical symptoms, not action label strings.
  final List<String> appointmentSymptoms;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions              = const [],
    this.showBookingPrompt    = false,
    DateTime? timestamp,
    this.hasImage             = false,
    this.appointmentSymptoms  = const [],
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
  PatientModel?     get patient       => _patient;

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
    } else {
      await _gemini.initSession(
        name: patient.name, diagnosis: 'General',
        daysSinceVisit: patient.daysSinceVisit, medications: [],
      );
    }
    _sessionReady = true;
    _messages.add(ChatMessage(
      text: 'Hi ${patient.name.split(' ').first}! 👋 I\'m CareLoop AI. '
          '${_todayQuestion ?? "How are you feeling today?"}\n\n'
          'I can help with your recovery, medications, or book an appointment. '
          'You can also send me a photo of your medication bill to understand it better!',
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

  // ── Send text message ──────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(ChatMessage(text: text, isUser: true));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessage(text);
    await _processResponse(response, text);
  }

  // ── Send message with image ───────────────────────────────────────────────
  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    final displayText = text.isEmpty ? '📷 [Photo sent]' : text;
    _messages.add(ChatMessage(
      text:     displayText,
      isUser:   true,
      hasImage: true,
    ));
    _thinking = true;
    notifyListeners();

    final promptText = text.isEmpty
        ? 'Please analyze this medication bill/receipt and explain what medications are listed, their dosages, and instructions.'
        : text;

    final response = await _gemini.sendMessageWithImage(
        promptText, imageBytes, mimeType);
    await _processResponse(response, promptText);
  }

  // ── Process AI response ───────────────────────────────────────────────────
  Future<void> _processResponse(GeminiResponse response, String userText) async {
    String       displayMsg = response.message;
    List<String> finalAct   = List.from(response.actions);
    bool         showBooking = false;

    // ── Agentic: join queue ────────────────────────────────────────────────
    if (response.actions.contains('join_queue')) {
      displayMsg = await _handleQueueJoin(response);
      finalAct.remove('join_queue');
    }

    // ── Agentic: appointment booking ───────────────────────────────────────
    if (response.actions.contains('book_appointment') || response.appointmentIntent) {
      showBooking = true;
      finalAct.remove('book_appointment');
    }

    // ── Agentic: health alert ──────────────────────────────────────────────
    if (response.actions.contains('alert_doctor') && _patient != null) {
      await _triggerHealthAlert(
        message:   userText,
        riskLevel: response.risk.name,
      );
      if (!displayMsg.contains('doctor')) {
        displayMsg = '$displayMsg\n\n✅ Your doctor has been notified.';
      }
    }

    // ✅ FIX 1: Store appointmentSymptoms from Gemini response
    _messages.add(ChatMessage(
      text:                displayMsg,
      isUser:              false,
      risk:                response.risk.name,
      actions:             finalAct,
      showBookingPrompt:   showBooking,
      appointmentSymptoms: response.appointmentSymptoms, // ← correct symptoms
    ));
    _thinking = false;
    notifyListeners();

    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id:               '',
        patientId:        _patient!.id,
        userMessage:      userText,
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

    String? doctorId = _patient!.assignedDoctorId;
    if (doctorId == null || doctorId.isEmpty) {
      final doctors = await _db.getAllDoctors();
      if (doctors.isNotEmpty) doctorId = doctors.first.id;
    }
    if (doctorId == null || doctorId.isEmpty) {
      await NotificationService.showHealthAlert(
          '${_patient!.name} reported: $message');
      return;
    }

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

    final alertId = await _db.createHealthAlert(alert);
    debugPrint('Health alert created: $alertId for doctor: $doctorId');

    await NotificationService.sendPushToUser(
      userId:         doctorId,
      userCollection: 'doctors',
      title:          '🚨 Patient Health Alert',
      body:           '${_patient!.name}: $message',
      channel:        'careloop_alerts',
    );

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

// ignore: non_constant_identifier_names
void debugPrint(String msg) {
  // ignore: avoid_print
  print(msg);
}