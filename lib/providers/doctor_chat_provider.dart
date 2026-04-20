import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide debugPrint;
import '../api_service.dart';
import '../models/doctor_model.dart';
import '../models/patient_model.dart';
import '../models/medication_model.dart';
import '../models/appointment_model.dart' as appointment;
import '../screens/bill_analyzer/bill_results_screen.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';
import '../models/health_alert_model.dart' as alert;

// ═══════════════════════════════════════════════════════════════════════════
// DOCTOR CHAT MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

class DoctorChatMessage {
  final String text;
  final bool isDoctor;
  final String? action;
  final List<PatientModel>? patientOptions;
  final bool hasImage;
  final DateTime timestamp;

  DoctorChatMessage({
    required this.text,
    required this.isDoctor,
    this.action,
    this.patientOptions,
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

      debugPrint('🔵 Doctor AI: Dr. ${doctor.name} has ${_myPatients.length} patient via prescriptions');

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
              '📊 Check specific patient status (medications & alerts)\n'
              '🚨 Review recent alerts (last 24 hours)\n'
              '📅 Request appointments with patients\n'
              '💬 Send messages to patients\n\n'
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
              '1. Check your `.env` for a valid Gemini API key\n'
              '2. Get a key from: https://aistudio.google.com/app/apikey\n'
              '3. Restart the app\n\n'
              'Error: ${e.toString().length > 200 ? e.toString().substring(0, 200) + "..." : e.toString()}',
          isDoctor: false,
        ));
      }
    } catch (e) {
      debugPrint('❌ Doctor AI: Failed to load patient: $e');
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
          '✅ Loaded ${_myPatients.length} patient via ${myMeds.length} prescriptions');
    } catch (e) {
      debugPrint('❌ Error loading patient: $e');
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

    try {
      final conversationHistory = _messages
          .take(_messages.length - 1)
          .map((m) => {
        "role": m.isDoctor ? "user" : "assistant",
        "content": m.text,
      })
          .toList();

      final res = await ApiService.sendChat(
        message: text,
        role: 'doctor',
        userId: _doctor?.id,
        conversationHistory: conversationHistory,
      );

      final backendMessage = res['message'] ?? 'No response';
      final actions = List<String>.from(res['actions'] ?? []);
      final lowerText = text.toLowerCase();
      final doctorLastName = _doctor?.name.split(' ').last ?? 'User';

      // ══════════════════════════════════════════════════════════════════
      // ACTION ROUTING — intercept known actions and handle locally.
      // The backend returns action *names* but the UI checks for specific
      // keys set here; they must match exactly.
      // ══════════════════════════════════════════════════════════════════

      // ── 1. REVIEW RECENT ALERTS (no patient selection needed) ─────────
      //       Fetches real health_alert documents from Firestore.
      if (actions.contains('review_recent_alerts') ||
          lowerText.contains('review alert') ||
          lowerText.contains('recent alert') ||
          lowerText.contains('check alert')) {
        final alertResult = await _handleReviewRecentAlerts();
        _messages.add(DoctorChatMessage(
          text: alertResult,
          isDoctor: false,
          action: 'review_recent_alerts',
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // ── 2. CHECK PATIENT STATUS (requires patient selection) ──────────
      //       Shows a patient picker; on selection calls
      //       checkPatientStatusFromSelection() which fetches real data.
      if (actions.contains('check_patient_status') ||
          lowerText.contains('check patient') ||
          lowerText.contains('patient status')) {
        if (_myPatients.isEmpty) {
          _messages.add(DoctorChatMessage(
            text: 'You don\'t have any patients yet. Patients will appear '
                'here once you prescribe medications to them.',
            isDoctor: false,
          ));
        } else {
          _messages.add(DoctorChatMessage(
            text: 'Hello Dr. $doctorLastName. Which patient would you like '
                'me to check on?',
            isDoctor: false,
            action: 'choose_patient_for_status', // ← key the UI checks
            patientOptions: List<PatientModel>.from(_myPatients),
          ));
        }
        _thinking = false;
        notifyListeners();
        return;
      }

      // ── 3. SEND APPOINTMENT REQUEST (requires patient selection) ──────
      //       Shows a patient picker; on selection calls
      //       sendAppointmentRequestToPatient() which fires the
      //       notification the patient can accept or decline.
      if (actions.contains('send_appointment_request') ||
          lowerText.contains('send appointment') ||
          lowerText.contains('appointment request') ||
          lowerText.contains('request appointment')) {
        if (_myPatients.isEmpty) {
          _messages.add(DoctorChatMessage(
            text: 'You don\'t have any patients with prescriptions yet. '
                'Please prescribe medication to a patient before '
                'requesting an appointment.',
            isDoctor: false,
          ));
        } else {
          _messages.add(DoctorChatMessage(
            text: 'Which patient would you like to send an appointment '
                'request to?',
            isDoctor: false,
            action: 'choose_appointment_patient', // ← key the UI checks
            patientOptions: List<PatientModel>.from(_myPatients),
          ));
        }
        _thinking = false;
        notifyListeners();
        return;
      }

      // ── 4. DEFAULT — show the AI's message as-is ──────────────────────
      _messages.add(DoctorChatMessage(
        text: backendMessage,
        isDoctor: false,
        action: actions.isNotEmpty ? actions.first : null,
      ));
    } catch (e) {
      _messages.add(DoctorChatMessage(
        text: '❌ Connection error: $e\n\nPlease check your connection and try again.',
        isDoctor: false,
      ));
    }

    _thinking = false;
    notifyListeners();
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

    // SPEC FEATURE 4: Review Recent Alerts (last 24 hours) - NO PATIENT SELECTION
    if (response.actions.contains('review_recent_alerts') ||
        query.toLowerCase().contains('recent alert') ||
        query.toLowerCase().contains('review alert')) {
      displayMsg = await _handleReviewRecentAlerts();
      _messages.add(DoctorChatMessage(
        text: displayMsg,
        isDoctor: false,
        action: 'review_recent_alerts',
      ));
      _thinking = false;
      notifyListeners();
      return;
    }

    // SPEC FEATURE 2: Check Patient Status - REQUIRES PATIENT SELECTION
    if (response.actions.contains('check_patient_status') ||
        query.toLowerCase().contains('check patient status')) {
      if (_myPatients.isEmpty) {
        displayMsg = 'You don\'t have any patient yet. Patients will appear here once you prescribe medications to them.';
        _messages.add(DoctorChatMessage(
          text: displayMsg,
          isDoctor: false,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // Show patient selection UI
      _messages.add(DoctorChatMessage(
        text: 'Which patient would you like to check on?',
        isDoctor: false,
        action: 'choose_patient_for_status',
        patientOptions: List<PatientModel>.from(_myPatients),
      ));
      _thinking = false;
      notifyListeners();
      return;
    }

    // SPEC FEATURE 3: Send Appointment Request (with calendar button)
    if (response.actions.contains('send_appointment_request') ||
        response.actions.contains('book_appointment') ||
        query.toLowerCase().contains('send appointment request')) {
      debugPrint('📅 Send appointment request triggered');
      debugPrint('   patientId: ${response.patientId}');
      debugPrint('   sendToPatient: ${response.sendToPatient}');
      debugPrint('   myPatients count: ${_myPatients.length}');

      if (response.patientId != null && response.sendToPatient != null) {
        await _handleSendAppointmentRequest(
            response.patientId, response.sendToPatient!);
        displayMsg =
        '$displayMsg\n\n✅ Appointment request sent with calendar button.';
      } else {
        if (_myPatients.isEmpty) {
          displayMsg = 'I could not identify a patient who has prescriptions yet. '
              'Please prescribe medication to a patient before requesting an appointment.';
        } else {
          debugPrint('✅ Showing patient selection UI');
          _messages.add(DoctorChatMessage(
            text: 'Which patient would you like to send an appointment request to?',
            isDoctor: false,
            action: 'choose_appointment_patient',
            patientOptions: List<PatientModel>.from(_myPatients),
          ));
          _thinking = false;
          notifyListeners();
          return;
        }
      }
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
  // SPEC FEATURE 4: REVIEW RECENT ALERTS (last 24 hours)
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _handleReviewRecentAlerts() async {
    if (_doctor == null) return 'No doctor context available.';

    try {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      // ✅ FIX: Query without orderBy to avoid index issues, filter in memory
      final alertsSnapshot = await FirebaseFirestore.instance
          .collection('health_alerts')
          .where('doctorId', isEqualTo: _doctor!.id)
          .get();

      // ✅ Also check notifications collection
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _doctor!.id)
          .where('type', isEqualTo: 'health_alert')
          .get();

      if (alertsSnapshot.docs.isEmpty && notificationsSnapshot.docs.isEmpty) {
        return '✅ **No Recent Alerts (Last 24 Hours)**\n\n'
            'Great news! None of your patient have triggered any health alerts in the past 24 hours.';
      }

      // ✅ Parse health_alerts
      final healthAlerts = alertsSnapshot.docs
          .map((doc) {
        try {
          return alert.HealthAlert.fromFirestore(doc);
        } catch (e) {
          debugPrint('❌ Error parsing health alert ${doc.id}: $e');
          return null;
        }
      })
          .whereType<appointment.HealthAlert>()
          .where((alert) => alert.createdAt.isAfter(yesterday))
          .toList();

      // ✅ Parse notifications
      final notificationAlerts = notificationsSnapshot.docs
          .map((doc) {
        try {
          final data = doc.data();
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
          if (timestamp.isAfter(yesterday)) {
            return {
              'patientName': data['metadata']?['patientName'] ?? 'Unknown',
              'message': data['message'] ?? '',
              'timestamp': timestamp,
              'type': data['type'] ?? 'health_alert',
            };
          }
        } catch (e) {
          debugPrint('❌ Error parsing notification ${doc.id}: $e');
        }
        return null;
      })
          .whereType<Map<String, dynamic>>()
          .toList();

      // Combine and sort
      final allAlerts = [...healthAlerts];
      allAlerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final recentAlerts = allAlerts.take(10).toList();

      if (recentAlerts.isEmpty && notificationAlerts.isEmpty) {
        return '✅ **No Recent Alerts (Last 24 Hours)**\n\n'
            'Great news! None of your patient have triggered any health alerts in the past 24 hours.';
      }

      final report = StringBuffer();
      report.writeln('🚨 **Recent Health Alerts (Last 24 Hours)**\n');
      report.writeln('Found ${recentAlerts.length + notificationAlerts.length} alert(s):\n');

      // Display health_alerts
      for (final alert in recentAlerts) {
        final timeAgo = _getTimeAgo(alert.createdAt);
        report.writeln('---');
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

      // Display notification alerts
      for (final alert in notificationAlerts) {
        final timeAgo = _getTimeAgo(alert['timestamp'] as DateTime);
        report.writeln('---');
        report.writeln('👤 **${alert['patientName']}**');
        report.writeln('⏰ $timeAgo');
        report.writeln('💬 ${alert['message']}');
        report.writeln('');
      }

      return report.toString();
    } catch (e) {
      debugPrint('❌ Error loading alerts: $e');
      return '❌ Unable to load recent alerts. Error: ${e.toString()}';
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
  // Shows detailed status for a specific patient including medications and alerts
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _handleCheckPatientStatus(
      String? patientIdHint, String query) async {
    if (_doctor == null) return 'No doctor context available.';

    PatientModel? target = _findPatient(patientIdHint, query);

    if (target == null) {
      final names = _myPatients.isEmpty
          ? 'No patient via prescriptions yet'
          : _myPatients.map((p) => p.name).join(', ');
      return 'I couldn\'t identify which patient you\'re asking about. '
          'Your patient (via prescriptions): $names. Could you specify?';
    }

    // Build detailed status report for this specific patient
    final report = StringBuffer();
    report.writeln('📊 **Status Report for ${target.name}**\n');
    report.writeln('━━━━━━━━━━━━━━━━━━━━');

    // Basic info
    report.writeln('👤 **Patient**: ${target.name}');
    report.writeln('📧 **Email**: ${target.email}');
    report.writeln('📋 **Diagnosis**: ${target.diagnosis ?? "Not recorded"}');
    report.writeln('');

    // Medication status
    final myMeds = _myPrescriptions[target.id] ?? [];

    if (myMeds.isEmpty) {
      report.writeln('💊 **Medications**: No active prescriptions from you');
    } else {
      final activeMeds = myMeds.where((m) => m.active).toList();
      final takenCount = activeMeds.where((m) => m.isTakenToday).length;
      final total = activeMeds.length;
      final adherenceRate =
      total > 0 ? (takenCount / total * 100).toStringAsFixed(0) : '0';

      report.writeln('💊 **Medications**: $total active prescription(s)');
      report.writeln('✅ **Today\'s Adherence**: $takenCount/$total taken ($adherenceRate%)');
      report.writeln('');

      // List all medications with today's status
      report.writeln('**Medication Details**:');
      for (final med in activeMeds) {
        final status = med.isTakenToday ? '✅ Taken' : '⚠️ Not taken yet';
        report.writeln('• ${med.name} (${med.dosage}) - $status');
        if (med.reminderTimes.isNotEmpty) {
          report.writeln('  Times: ${med.reminderTimes.join(", ")}');
        }
      }

      report.writeln('');
    }

    // Recent alerts for this specific patient
    try {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      final alertsSnapshot = await FirebaseFirestore.instance
          .collection('health_alerts')
          .where('doctorId', isEqualTo: _doctor!.id)
          .where('patientId', isEqualTo: target.id)
          .get();

      final patientAlerts = alertsSnapshot.docs
          .map((doc) {
        try {
          return alert.HealthAlert.fromFirestore(doc);
        } catch (e) {
          return null;
        }
      })
          .whereType<alert.HealthAlert>()
          .where((alert) => alert.createdAt.isAfter(yesterday))
          .toList();

      if (patientAlerts.isEmpty) {
        report.writeln('🟢 **Recent Alerts**: No alerts in the last 24 hours');
      } else {
        report.writeln('🚨 **Recent Alerts (24h)**: ${patientAlerts.length} alert(s)');
        report.writeln('');

        for (final alert in patientAlerts.take(5)) {
          final timeAgo = _getTimeAgo(alert.createdAt);
          report.writeln('---');
          report.writeln('⏰ $timeAgo');
          report.writeln('⚠️ Risk: ${alert.riskLevel.toUpperCase()}');
          report.writeln('💬 ${alert.message}');
          report.writeln('');
        }
      }
    } catch (e) {
      report.writeln('⚠️ Unable to load recent alerts');
    }

    return report.toString();
  }

  // Helper method to handle patient status check when patient is selected from UI
  Future<void> checkPatientStatusFromSelection(PatientModel patient) async {
    if (_doctor == null) return;

    _messages.add(DoctorChatMessage(
      text: 'Checking status for ${patient.name}...',
      isDoctor: true,
    ));
    notifyListeners();

    final statusReport = await _handleCheckPatientStatus(patient.id, '');

    _messages.add(DoctorChatMessage(
      text: statusReport,
      isDoctor: false,
      action: 'patient_status_checked',
    ));
    notifyListeners();
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
        doctorId: _doctor!.id,
        doctorName: _doctor!.name,
        message: message,
      );

      await NotificationService.sendPushToUser(
        userId: target.id,
        userCollection: 'patient',
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

  Future<void> sendAppointmentRequestToPatient(PatientModel patient) async {
    if (_doctor == null) return;

    _messages.add(DoctorChatMessage(
      text: '📩 Sending appointment request to ${patient.name}…',
      isDoctor: true,
    ));
    notifyListeners();

    try {
      // Create a tracked appointment request document in Firestore so the
      // patient's accept/decline can be linked back to this doctor.
      final requestRef = await FirebaseFirestore.instance
          .collection('appointment_requests')
          .add({
        'doctorId': _doctor!.id,
        'doctorName': _doctor!.name,
        'patientId': patient.id,
        'patientName': patient.name,
        'status': 'pending',          // updated to 'accepted' / 'declined'
        'createdAt': FieldValue.serverTimestamp(),
      });

      final requestMessage =
          'Dr. ${_doctor!.name} would like to schedule an appointment with you. '
          'Please choose a suitable time.';

      // Send the notification that will show Accept / Decline buttons in
      // the patient's inbox (InboxService._isAppointmentRequest checks
      // for action == 'open_appointments', doctorId, and requestMessage).
      await InboxService.sendAppointmentRequestNotification(
        userId: patient.id,
        doctorId: _doctor!.id,
        doctorName: _doctor!.name,
        message: requestMessage,
        requestId: requestRef.id, // ← new field for tracking
      );

      // Push notification so the patient is alerted immediately.
      await NotificationService.sendPushToUser(
        userId: patient.id,
        userCollection: 'patient',
        title: '📅 Appointment Request — Dr. ${_doctor!.name}',
        body: requestMessage,
        channel: 'careloop_queue',
      );

      _messages.add(DoctorChatMessage(
        text: '✅ Appointment request sent to ${patient.name}.\n\n'
            'They will receive a notification and can accept or decline '
            'directly from their inbox.',
        isDoctor: false,
        action: 'send_appointment_request',
      ));
    } catch (e) {
      debugPrint('❌ Error sending appointment request: $e');
      _messages.add(DoctorChatMessage(
        text: '❌ Failed to send appointment request: $e',
        isDoctor: false,
      ));
    }
    notifyListeners();
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
        doctorId: _doctor!.id,
        message: message,
      );

      await NotificationService.sendPushToUser(
        userId: target.id,
        userCollection: 'patient',
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