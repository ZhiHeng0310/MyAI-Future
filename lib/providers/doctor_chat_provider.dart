import 'dart:typed_data';
import 'package:flutter/material.dart' hide debugPrint;
import '../models/doctor_model.dart';
import '../models/patient_model.dart';
import '../models/medication_model.dart';
import '../models/appointment_model.dart';
import '../models/health_alert_model.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DOCTOR CHAT MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

class DoctorChatMessage {
  final String text;
  final bool isDoctor;
  final String? action;
  final bool hasImage;
  final DateTime timestamp;

  DoctorChatMessage({
    required this.text,
    required this.isDoctor,
    this.action,
    this.hasImage = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════
// DOCTOR CHAT PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class DoctorChatProvider extends ChangeNotifier {
  GeminiService _gemini = GeminiService(role: GeminiRole.doctor);
  final _db = FirestoreService();

  final List<DoctorChatMessage> _messages = [];
  bool _thinking = false;
  bool _sessionReady = false;
  DoctorModel? _doctor;

  List<PatientModel> _myPatients = [];
  Map<String, List<Medication>> _myPrescriptions = {};

  List<DoctorChatMessage> get messages => _messages;
  bool get thinking => _thinking;
  bool get sessionReady => _sessionReady;
  List<PatientModel> get myPatients => _myPatients;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> initSession(DoctorModel doctor) async {
    if (_sessionReady) return;
    _doctor = doctor;

    try {
      await _loadMyPatients();

      final summaries = _myPatients
          .map((p) => '${p.name} (Dx: ${p.diagnosis ?? "N/A"})')
          .toList();

      debugPrint('🔵 Doctor AI: Dr. ${doctor.name} has ${_myPatients.length} patients via prescriptions');

      try {
        await _gemini.initSession(
          name: doctor.name,
          diagnosis: '',
          daysSinceVisit: 0,
          medications: [],
          doctorId: doctor.id,
          patientSummaries: summaries,
        );

        _sessionReady = true;
        _messages.add(DoctorChatMessage(
          text: 'Hello Dr. ${doctor.name.split(' ').last}! 👋 I\'m your CareLoop AI assistant.\n\n'
              'You have ${_myPatients.length} patient(s) via prescriptions.\n\n'
              'I can help you:\n'
              '👥 Check how your patients are doing today\n'
              '📊 Review medication adherence (for your prescriptions)\n'
              '💬 Send messages to patients\n'
              '📅 Request appointments\n'
              '🚨 Review recent alerts (last 24 hours)\n\n'
              'What would you like to do?',
          isDoctor: false,
        ));

        debugPrint('✅ Doctor AI: Session initialized successfully');
      } catch (e) {
        debugPrint('❌ Doctor AI: Gemini initialization failed: $e');
        _sessionReady = true;
        _messages.add(DoctorChatMessage(
          text: '⚠️ **AI Connection Issue**\n\n'
              'I\'m having trouble connecting to the AI service.\n\n'
              '**To fix:**\n'
              '1. Check your `env.json` for a valid Gemini API key\n'
              '2. Get a key from: https://aistudio.google.com/app/apikey\n'
              '3. Restart the app\n\n'
              'Error: ${e.toString().length > 200 ? e.toString().substring(0, 200) + "..." : e.toString()}',
          isDoctor: false,
        ));
      }
    } catch (e) {
      debugPrint('❌ Doctor AI: Failed to load patients: $e');
      _sessionReady = true;
      _messages.add(DoctorChatMessage(
        text: '⚠️ **Database Connection Issue**\n\n'
            'I couldn\'t load your patient list.\n\nError: $e',
        isDoctor: false,
      ));
    }

    notifyListeners();
  }

  Future<void> _loadMyPatients() async {
    if (_doctor == null) return;

    try {
      final allMeds = await _db.getAllMedications();
      // FIX: use doctorId field
      final myMeds =
      allMeds.where((m) => m.doctorId == _doctor!.id).toList();
      final patientIds = myMeds.map((m) => m.patientId).toSet().toList();

      _myPatients = [];
      _myPrescriptions = {};

      for (final patientId in patientIds) {
        try {
          final patient = await _db.getPatient(patientId);
          if (patient != null) {
            _myPatients.add(patient);
            _myPrescriptions[patientId] =
                myMeds.where((m) => m.patientId == patientId).toList();
          }
        } catch (_) {}
      }

      debugPrint(
          '✅ Loaded ${_myPatients.length} patients via ${myMeds.length} prescriptions');
    } catch (e) {
      debugPrint('❌ Error loading patients: $e');
      _myPatients = [];
      _myPrescriptions = {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MESSAGE HANDLING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(DoctorChatMessage(text: text, isDoctor: true));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessage(text);
    await _processResponse(response, text);
  }

  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    final displayText =
    text.isEmpty ? '📷 [Medical image sent for analysis]' : text;
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

  // ══════════════════════════════════════════════════════════════════════════
  // PROCESS RESPONSE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _processResponse(
      GeminiResponse response, String query) async {
    String displayMsg = response.message;

    if (response.isError) {
      _messages.add(DoctorChatMessage(
        text: displayMsg,
        isDoctor: false,
        action: 'error',
      ));
      _thinking = false;
      notifyListeners();
      return;
    }

    // SPEC FEATURE 1: How Are My Patients Today?
    if (response.actions.contains('review_my_patients') ||
        query.toLowerCase().contains('how are my patients') ||
        query.toLowerCase().contains('patient status') ||
        query.toLowerCase().contains('my patients today')) {
      displayMsg = await _handleHowAreMyPatients();
    }

    // SPEC FEATURE 4: Review Recent Alerts (last 24 hours)
    if (response.actions.contains('review_recent_alerts') ||
        query.toLowerCase().contains('recent alert') ||
        query.toLowerCase().contains('review alert')) {
      displayMsg = await _handleReviewRecentAlerts();
    }

    // SPEC FEATURE 2: Check Patient Status
    if (response.actions.contains('check_patient_status')) {
      displayMsg =
      await _handleCheckPatientStatus(response.patientId, query);
    }

    // SPEC FEATURE 3: Send Appointment Request (with calendar button)
    if (response.actions.contains('send_appointment_request') &&
        response.sendToPatient != null) {
      await _handleSendAppointmentRequest(
          response.patientId, response.sendToPatient!);
      displayMsg =
      '$displayMsg\n\n✅ Appointment request sent with calendar button.';
    }

    // Send patient message
    if (response.actions.contains('send_patient_message') &&
        response.sendToPatient != null) {
      await _handleSendToPatient(
          response.patientId, response.sendToPatient!, 'doctor_note');
      displayMsg = '$displayMsg\n\n✅ Message delivered to patient.';
    }

    _messages.add(DoctorChatMessage(
      text: displayMsg,
      isDoctor: false,
      action: response.actions.isNotEmpty ? response.actions.first : null,
    ));
    _thinking = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 1: HOW ARE MY PATIENTS TODAY?
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _handleHowAreMyPatients() async {
    if (_doctor == null) return 'No doctor context available.';

    if (_myPatients.isEmpty) {
      return 'You don\'t have any patients yet. Patients will appear here once you prescribe medications to them.';
    }

    // Refresh patient data for latest adherence
    await _loadMyPatients();

    final report = StringBuffer();
    report.writeln('📊 **Patient Status Report**\n');
    report.writeln(
        'You have ${_myPatients.length} patient(s) via prescriptions:\n');

    for (final patient in _myPatients) {
      report.writeln('━━━━━━━━━━━━━━━━━━━━');
      report.writeln('👤 **${patient.name}**');
      report.writeln(
          '📋 Diagnosis: ${patient.diagnosis ?? "Not recorded"}');

      final myMeds = _myPrescriptions[patient.id] ?? [];

      if (myMeds.isEmpty) {
        report.writeln('💊 No active prescriptions from you');
      } else {
        final activeMeds = myMeds.where((m) => m.active).toList();
        final takenCount = activeMeds.where((m) => m.isTakenToday).length;
        final total = activeMeds.length;
        final adherenceRate =
        total > 0 ? (takenCount / total * 100).toStringAsFixed(0) : '0';

        report.writeln('💊 **Your Prescriptions**: $total medication(s)');
        report.writeln(
            '✅ **Adherence**: $takenCount/$total taken today ($adherenceRate%)');

        final missed =
        activeMeds.where((m) => !m.isTakenToday).toList();
        if (missed.isNotEmpty) {
          report.writeln('⚠️ **Missed Today**:');
          for (final med in missed) {
            report.writeln('   • ${med.name} (${med.dosage})');
          }
        }
      }

      report.writeln('');
    }

    // FIX: use getRecentAlertsForDoctor
    try {
      final alerts =
      await _db.getRecentAlertsForDoctor(_doctor!.id);
      if (alerts.isNotEmpty) {
        report.writeln('\n🚨 **Recent Alerts (24h)**: ${alerts.length}');
        report.writeln('Use "Review recent alerts" to see details.');
      } else {
        report.writeln('\n✅ No recent alerts in the last 24 hours.');
      }
    } catch (_) {}

    return report.toString();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 4: REVIEW RECENT ALERTS (last 24 hours)
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _handleReviewRecentAlerts() async {
    if (_doctor == null) return 'No doctor context available.';

    try {
      // FIX: use getRecentAlertsForDoctor (correct method on FirestoreService)
      final recent = await _db.getRecentAlertsForDoctor(_doctor!.id);

      if (recent.isEmpty) {
        return '✅ **No recent alerts.**\n\nAll your patients are doing well!';
      }

      final report = StringBuffer();
      report.writeln('🚨 **Recent Alerts (Last 24 Hours)**\n');
      report.writeln('Found ${recent.length} alert(s):\n');

      for (final alert in recent) {
        final timeAgo = _getTimeAgo(alert.createdAt);
        report.writeln('━━━━━━━━━━━━━━━━━━━━');
        report.writeln('👤 **${alert.patientName}**');
        report.writeln('⏰ $timeAgo');
        report.writeln('⚠️ Risk: ${alert.riskLevel.toUpperCase()}');
        report.writeln('💬 Message: ${alert.message}');
        report.writeln('📊 Status: ${alert.status}');
        if (alert.doctorResponse != null) {
          report.writeln('💬 Your response: ${alert.doctorResponse}');
        }
        report.writeln('');
      }

      return report.toString();
    } catch (e) {
      debugPrint('❌ Error loading alerts: $e');
      return '❌ Unable to load recent alerts. Please try again.';
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 60) return '${diff.inMinutes} minute(s) ago';
    if (diff.inHours < 24) return '${diff.inHours} hour(s) ago';
    return '${diff.inDays} day(s) ago';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 2: CHECK PATIENT STATUS
  // Sends "How are you feeling today?" notification to patient
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _handleCheckPatientStatus(
      String? patientIdHint, String query) async {
    if (_doctor == null) return 'No doctor context available.';

    PatientModel? target = _findPatient(patientIdHint, query);

    if (target == null) {
      final names = _myPatients.isEmpty
          ? 'No patients via prescriptions yet'
          : _myPatients.map((p) => p.name).join(', ');
      return 'I couldn\'t identify which patient you\'re asking about. '
          'Your patients (via prescriptions): $names. Could you specify?';
    }

    await _sendCheckStatusNotification(target);

    return 'I\'ve sent a notification to **${target.name}** asking: "How are you feeling today?"\n\n'
        'They will reply, and you\'ll receive their response via notification.';
  }

  Future<void> _sendCheckStatusNotification(PatientModel patient) async {
    if (_doctor == null) return;

    try {
      await _db.createPatientInboxMessage(
        patientId: patient.id,
        message:
        '👨‍⚕️ Dr. ${_doctor!.name} is checking on you: "How are you feeling today?"',
        type: 'doctor_check',
        doctorId: _doctor!.id,
      );

      await InboxService.sendDoctorMessage(
        userId: patient.id,
        doctorName: _doctor!.name,
        message: 'How are you feeling today?',
        metadata: {'action': 'doctor_check', 'doctorId': _doctor!.id},
      );

      await NotificationService.sendPushToUser(
        userId: patient.id,
        userCollection: 'patients',
        title: '👨‍⚕️ Dr. ${_doctor!.name}',
        body: 'How are you feeling today?',
        channel: 'careloop_queue',
      );

      debugPrint(
          '✅ Sent check status notification to ${patient.name}');
    } catch (e) {
      debugPrint(
          '❌ Error sending check status notification: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 3: SEND APPOINTMENT REQUEST (with calendar button)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleSendAppointmentRequest(
      String? patientIdHint, String message) async {
    if (_doctor == null) return;

    final target = _findPatient(patientIdHint, '') ??
        (_myPatients.isNotEmpty ? _myPatients.first : null);

    if (target == null) {
      debugPrint('❌ No target patient found for appointment request');
      return;
    }

    try {
      // Notification must include hint to open calendar (action metadata)
      await _db.createPatientInboxMessage(
        patientId: target.id,
        message: '📅 Dr. ${_doctor!.name} requests an appointment: $message\n\n'
            'Tap to open calendar and book your appointment.',
        type: 'appointment_request',
        doctorId: _doctor!.id,
      );

      await InboxService.sendAppointmentRequestNotification(
        userId: target.id,
        doctorName: _doctor!.name,
        message: message,
      );

      await NotificationService.sendPushToUser(
        userId: target.id,
        userCollection: 'patients',
        title: '📅 Appointment Request — Dr. ${_doctor!.name}',
        body: message,
        channel: 'careloop_queue',
      );

      debugPrint(
          '✅ Sent appointment request to ${target.name} with calendar button');
    } catch (e) {
      debugPrint('❌ Error sending appointment request: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEND GENERAL MESSAGE TO PATIENT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleSendToPatient(
      String? patientIdHint, String message, String type) async {
    if (_doctor == null) return;

    final target = _findPatient(patientIdHint, '') ??
        (_myPatients.isNotEmpty ? _myPatients.first : null);

    if (target == null) {
      debugPrint('❌ No target patient found');
      return;
    }

    try {
      await _db.createPatientInboxMessage(
        patientId: target.id,
        message: '📩 Message from Dr. ${_doctor!.name}: $message',
        type: type,
        doctorId: _doctor!.id,
      );

      await InboxService.sendDoctorMessage(
        userId: target.id,
        doctorName: _doctor!.name,
        message: message,
      );

      await NotificationService.sendPushToUser(
        userId: target.id,
        userCollection: 'patients',
        title: '👨‍⚕️ Dr. ${_doctor!.name}',
        body: message,
        channel: 'careloop_queue',
      );

      debugPrint('✅ Sent message to patient ${target.name}');
    } catch (e) {
      debugPrint('❌ Error sending message to patient: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPER: Find patient by hint or query
  // ══════════════════════════════════════════════════════════════════════════

  PatientModel? _findPatient(String? hint, String query) {
    if (hint != null && hint.isNotEmpty) {
      try {
        return _myPatients.firstWhere((p) =>
        p.id == hint ||
            p.name.toLowerCase().contains(hint.toLowerCase()));
      } catch (_) {}
    }

    if (query.isNotEmpty) {
      for (final p in _myPatients) {
        final first = p.name.split(' ').first.toLowerCase();
        if (query.toLowerCase().contains(first)) {
          return p;
        }
      }
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> resetSession(DoctorModel? doctor) async {
    _messages.clear();
    _sessionReady = false;
    _gemini = GeminiService(role: GeminiRole.doctor);
    _myPatients = [];
    _myPrescriptions = {};
    notifyListeners();
    if (doctor != null) await initSession(doctor);
  }

  void clear() {
    _messages.clear();
    _sessionReady = false;
    _gemini = GeminiService(role: GeminiRole.doctor);
    _myPatients = [];
    _myPrescriptions = {};
    notifyListeners();
  }
}

void debugPrint(String msg) => print(msg);