import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/doctor_model.dart';
import '../models/patient_model.dart';
import '../services/gemini_service.dart' hide FirestoreService;
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class DoctorChatMessage {
  final String text;
  final bool   isDoctor;
  final String? action;
  final bool    hasImage;
  final DateTime timestamp;
  DoctorChatMessage({
    required this.text,
    required this.isDoctor,
    this.action,
    this.hasImage = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class DoctorChatProvider extends ChangeNotifier {
  GeminiService _gemini = GeminiService(role: GeminiRole.doctor);
  final _db = FirestoreService();

  final List<DoctorChatMessage> _messages = [];
  bool          _thinking     = false;
  bool          _sessionReady = false;
  DoctorModel?  _doctor;
  List<PatientModel> _patients = [];

  List<DoctorChatMessage> get messages      => _messages;
  bool                    get thinking      => _thinking;
  bool                    get sessionReady  => _sessionReady;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> initSession(DoctorModel doctor) async {
    if (_sessionReady) return;
    _doctor = doctor;

    _patients = await _db.getPatientsForDoctor(doctor.id);
    final summaries = _patients
        .map((p) => '${p.name} (Dx: ${p.diagnosis ?? "N/A"})')
        .toList();

    await _gemini.initSession(
      name:             doctor.name,
      diagnosis:        '',
      daysSinceVisit:   0,
      medications:      [],
      doctorId:         doctor.id,
      patientSummaries: summaries,
    );

    _sessionReady = true;
    _messages.add(DoctorChatMessage(
      text: 'Hello Dr. ${doctor.name.split(' ').last}! 👋 I\'m your CareLoop AI assistant. '
          'I can help you check on patients, send them messages, or request appointments.\n\n'
          'You currently have ${_patients.length} assigned patient(s). '
          'You can also send me medical images or reports for clinical analysis. '
          'How can I help you today?',
      isDoctor: false,
    ));
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  Future<void> resetSession(DoctorModel? doctor) async {
    _messages.clear();
    _sessionReady = false;
    _gemini       = GeminiService(role: GeminiRole.doctor);
    notifyListeners();
    if (doctor != null) await initSession(doctor);
  }

  // ── Send text message ──────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(DoctorChatMessage(text: text, isDoctor: true));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessage(text);
    await _processResponse(response, text);
  }

  // ── Send message with image ───────────────────────────────────────────────
  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    final displayText = text.isEmpty ? '📷 [Medical image sent for analysis]' : text;
    _messages.add(DoctorChatMessage(
      text: displayText,
      isDoctor: true,
      hasImage: true,
    ));
    _thinking = true;
    notifyListeners();

    final promptText = text.isEmpty
        ? 'Please analyze this medical image/report and provide clinical observations.'
        : text;

    final response = await _gemini.sendMessageWithImage(
        promptText, imageBytes, mimeType);
    await _processResponse(response, promptText);
  }

  // ── Process response ──────────────────────────────────────────────────────
  Future<void> _processResponse(GeminiResponse response, String query) async {
    String displayMsg = response.message;

    // ── Agentic: check patient status ─────────────────────────────────────
    if (response.actions.contains('check_patient_status')) {
      displayMsg = await _handleCheckPatient(
          response.patientId, query);
    }

    // ── Agentic: send appointment request to patient ───────────────────────
    if (response.actions.contains('send_appointment_request') &&
        response.sendToPatient != null) {
      await _handleSendToPatient(
        response.patientId,
        response.sendToPatient!,
        'appointment_request',
      );
      displayMsg = '$displayMsg\n\n✅ Appointment request sent to patient.';
    }

    // ── Agentic: send message to patient ──────────────────────────────────
    if (response.actions.contains('send_patient_message') &&
        response.sendToPatient != null) {
      await _handleSendToPatient(
        response.patientId,
        response.sendToPatient!,
        'doctor_note',
      );
      displayMsg = '$displayMsg\n\n✅ Message delivered to patient.';
    }

    _messages.add(DoctorChatMessage(
      text:     displayMsg,
      isDoctor: false,
      action:   response.actions.isNotEmpty ? response.actions.first : null,
    ));
    _thinking = false;
    notifyListeners();
  }

  // ── Check patient status ──────────────────────────────────────────────────
  Future<String> _handleCheckPatient(
      String? patientIdHint, String query) async {
    if (_doctor == null) return 'No doctor context available.';

    PatientModel? target;
    if (patientIdHint != null && patientIdHint.isNotEmpty) {
      try {
        target = _patients.firstWhere(
                (p) => p.id == patientIdHint ||
                p.name.toLowerCase().contains(patientIdHint.toLowerCase()));
      } catch (_) {}
    }
    if (target == null && _patients.isNotEmpty) {
      for (final p in _patients) {
        final first = p.name.split(' ').first.toLowerCase();
        if (query.toLowerCase().contains(first)) {
          target = p;
          break;
        }
      }
    }

    if (target == null) {
      final names = _patients.isEmpty
          ? 'No assigned patients yet'
          : _patients.map((p) => p.name).join(', ');
      return 'I couldn\'t identify which patient you\'re asking about. '
          'Your assigned patients are: $names. Could you specify?';
    }

    final diagnosis    = target.diagnosis ?? 'not recorded';
    final daysStr      = target.daysSinceVisit > 0
        ? '${target.daysSinceVisit} days since last visit'
        : 'no visit on record';
    final hasDoctor    = target.assignedDoctorId == _doctor!.id;

    return 'Status for **${target.name}**: '
        'Diagnosis: $diagnosis. $daysStr. '
        '${hasDoctor ? "Assigned to you." : "Not assigned to you."} '
        'Would you like to send them a message or request an appointment?';
  }

  // ── Send message/request to patient ──────────────────────────────────────
  Future<void> _handleSendToPatient(
      String?     patientIdHint,
      String      message,
      String      type,
      ) async {
    if (_doctor == null) return;

    PatientModel? target;
    if (patientIdHint != null) {
      try {
        target = _patients.firstWhere(
                (p) => p.id == patientIdHint ||
                p.name.toLowerCase().contains(patientIdHint.toLowerCase()));
      } catch (_) {}
    }
    target ??= _patients.isNotEmpty ? _patients.first : null;
    if (target == null) return;

    await _db.createPatientInboxMessage(
      patientId: target.id,
      message:   '📩 Message from Dr. ${_doctor!.name}: $message',
      type:      type,
      doctorId:  _doctor!.id,
    );

    // Send push notification to patient
    await NotificationService.sendPushToUser(
      userId:         target.id,
      userCollection: 'patients',
      title:          '📩 Dr. ${_doctor!.name}',
      body:           message,
      channel:        'careloop_queue',
    );
  }

  void clear() {
    _messages.clear();
    _sessionReady = false;
    _gemini       = GeminiService(role: GeminiRole.doctor);
    notifyListeners();
  }
}