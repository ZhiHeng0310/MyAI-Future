import 'package:flutter/material.dart';
import '../models/checkin_model.dart';
import '../models/patient_model.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final String? risk;
  final List<String> actions;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatProvider extends ChangeNotifier {
  final _gemini = GeminiService();
  final _db = FirestoreService();

  final List<ChatMessage> _messages = [];
  bool _thinking = false;
  bool _sessionReady = false;
  String? _todayQuestion;
  PatientModel? _patient;

  List<ChatMessage> get messages => _messages;
  bool get thinking => _thinking;
  String? get todayQuestion => _todayQuestion;

  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;

    if (patient.diagnosis != null) {
      await _gemini.initSession(
        name: patient.name,
        diagnosis: patient.diagnosis!,
        daysSinceVisit: patient.daysSinceVisit,
        medications: [],
      );
      _todayQuestion = await _gemini.generateCheckInQuestion(
        patient.diagnosis!,
        patient.daysSinceVisit,
      );
    }

    _sessionReady = true;

    // Welcome message
    _messages.add(ChatMessage(
      text: 'Hi ${patient.name}! I\'m your CareLoop AI. ${_todayQuestion ?? "How are you feeling today?"}',
      isUser: false,
    ));
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(text: text, isUser: true));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessage(text);

    _messages.add(ChatMessage(
      text: response.message,
      isUser: false,
      risk: response.risk.name,
      actions: response.actions,
    ));

    _thinking = false;
    notifyListeners();

    // Persist to Firestore & trigger actions
    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id: '',
        patientId: _patient!.id,
        userMessage: text,
        aiResponse: response.message,
        risk: response.risk.name,
        actionsTriggered: response.actions,
        createdAt: DateTime.now(),
      ));

      for (final action in response.actions) {
        await _handleAction(action, response.message);
      }
    }
  }

  Future<void> _handleAction(String action, String context) async {
    if (_patient == null) return;
    switch (action) {
      case 'alert_doctor':
        await _db.createAlert(
          patientId: _patient!.id,
          type: 'doctor_alert',
          message: 'Patient reported: $context',
          clinicId: 'clinic_main',
        );
        break;
      case 'suggest_revisit':
        await _db.createAlert(
          patientId: _patient!.id,
          type: 'revisit',
          message: 'AI recommends revisit: $context',
        );
        break;
      case 'increase_priority':
        // Handled via QueueProvider if patient is in queue
        break;
      case 'remind_medication':
        // Push notification handled by Firebase Messaging
        break;
    }
  }

  void clearChat() {
    _messages.clear();
    _sessionReady = false;
    notifyListeners();
  }
}
