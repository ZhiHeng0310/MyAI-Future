import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/checkin_model.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/appointment_model.dart';
import '../models/medication_model.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';
import 'queue_provider.dart';

// ─── Chat Message ─────────────────────────────────────────────────────────────

class ChatMessage {
  final String       text;
  final bool         isUser;
  final String?      risk;
  final List<String> actions;
  final DateTime     timestamp;
  final bool         hasImage;

  /// True = show inline calendar date picker
  final bool showCalendarPicker;

  /// Symptoms carried forward when user picks a date
  final List<String> appointmentSymptoms;

  /// Feature 4: document analysis card
  final DocumentAnalysis? documentAnalysis;

  /// Feature 3: medication status card
  final MedStatusResult? medicationStatus;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions              = const [],
    DateTime? timestamp,
    this.hasImage             = false,
    this.showCalendarPicker   = false,
    this.appointmentSymptoms  = const [],
    this.documentAnalysis,
    this.medicationStatus,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Result of medication status check (Feature 3)
class MedStatusResult {
  final List<Medication> all;
  final List<Medication> taken;
  final List<Medication> missed;

  const MedStatusResult({
    required this.all,
    required this.taken,
    required this.missed,
  });

  bool   get allTaken      => missed.isEmpty && all.isNotEmpty;
  bool   get noMeds        => all.isEmpty;
  double get adherenceRate => all.isEmpty ? 1.0 : taken.length / all.length;
}

// ─── Chat Provider ────────────────────────────────────────────────────────────

class ChatProvider extends ChangeNotifier {
  GeminiService  _gemini        = GeminiService(role: GeminiRole.patient);
  final _db                     = FirestoreService();
  QueueProvider? _queueProvider;

  final List<ChatMessage> _messages = [];
  bool           _thinking          = false;
  bool           _sessionReady      = false;
  String?        _todayQuestion;

  // Loaded from Firestore at init — injected into Gemini context
  PatientModel?  _patient;
  DoctorModel?   _assignedDoctor;
  List<Medication> _loadedMeds      = [];

  // Held while user picks a date from the calendar
  List<String>   _pendingSymptoms   = [];

  // ── Getters ───────────────────────────────────────────────────────────────
  List<ChatMessage> get messages     => _messages;
  bool              get thinking     => _thinking;
  bool              get sessionReady => _sessionReady;
  String?           get todayQuestion => _todayQuestion;
  PatientModel?     get patient      => _patient;

  void setQueueProvider(QueueProvider qp) => _queueProvider = qp;

  // ── Session init — loads all patient context FIRST ────────────────────────
  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;

    // 1. Load medications from Firestore
    try {
      _loadedMeds = await _db.getMedicationsForPatient(patient.id);
    } catch (_) {
      _loadedMeds = [];
    }

    // 2. Load assigned doctor
    if (patient.assignedDoctorId != null) {
      try {
        _assignedDoctor = await _db.getDoctor(patient.assignedDoctorId!);
      } catch (_) {
        _assignedDoctor = null;
      }
    }

    // 3. If still no assigned doctor but has meds, find doctor from meds
    if (_assignedDoctor == null && _loadedMeds.isNotEmpty) {
      try {
        final doctors = await _db.getAllDoctors();
        if (doctors.isNotEmpty) {
          // Try to match by seeing who has this patient
          final patientsOfFirst = await _db.getPatientsForDoctor(doctors.first.id);
          if (patientsOfFirst.any((p) => p.id == patient.id)) {
            _assignedDoctor = doctors.first;
          } else {
            // Just use first available
            _assignedDoctor = doctors.first;
          }
        }
      } catch (_) {}
    }

    // 4. Build medication names list for Gemini context
    final medNames = _loadedMeds
        .map((m) => '${m.name} ${m.dosage} (${m.frequency})')
        .toList();

    // 5. Init Gemini session with ALL real patient data
    try {
      await _gemini.initSession(
        name:               patient.name,
        diagnosis:          patient.diagnosis ?? 'General',
        daysSinceVisit:     patient.daysSinceVisit,
        medications:        medNames,
        assignedDoctorName: _assignedDoctor?.name,
      );
    } catch (e) {
      // Gemini failed to init — still allow chat with fallback
      debugPrint('⚠️ Gemini init failed: $e');
    }

    // 6. Generate personalised check-in question
    _todayQuestion = await _gemini.generateCheckInQuestion(
        patient.diagnosis ?? 'General', patient.daysSinceVisit);

    _sessionReady = true;

    final firstName = patient.name.split(' ').first;
    final medNote   = _loadedMeds.isEmpty
        ? ''
        : '\n\nYou have ${_loadedMeds.length} medication(s) prescribed. '
        'Ask me to check if you\'ve taken them today!';

    _messages.add(ChatMessage(
      text: 'Hi $firstName! 👋 I\'m CareLoop AI. '
          '${_todayQuestion ?? "How are you feeling today?"}'
          '$medNote\n\n'
          'I can 📅 book appointments, 🚨 alert your doctor, '
          '💊 check your meds, or 📄 scan your medical bills.',
      isUser: false,
    ));
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  Future<void> resetSession(PatientModel? patient) async {
    _messages.clear();
    _sessionReady    = false;
    _todayQuestion   = null;
    _assignedDoctor  = null;
    _loadedMeds      = [];
    _pendingSymptoms = [];
    _gemini          = GeminiService(role: GeminiRole.patient);
    notifyListeners();
    if (patient != null) await initSession(patient);
  }

  // ── Send text ─────────────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(ChatMessage(text: text, isUser: true));
    _thinking = true;
    notifyListeners();
    final response = await _gemini.sendMessage(text);
    await _processResponse(response, text);
  }

  // ── Send with image (Feature 4 — document scan) ──────────────────────────
  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    final display = text.isEmpty ? '📷 Document sent for analysis' : text;
    _messages.add(ChatMessage(text: display, isUser: true, hasImage: true));
    _thinking = true;
    notifyListeners();

    final prompt = text.isEmpty
        ? 'Analyse this medication bill / prescription / medical report. '
        'Provide a clear structured breakdown that my patient can easily understand.'
        : text;

    final response = await _gemini.sendMessageWithImage(prompt, imageBytes, mimeType);
    await _processResponse(response, prompt);
  }

  // ── Feature 1: Patient selected a date from calendar ─────────────────────
  Future<void> onDateSelected(DateTime date) async {
    if (_patient == null) return;

    _messages.add(ChatMessage(
      text:   '📅 I\'d like to book on ${_fmtDate(date)}',
      isUser: true,
    ));
    _thinking = true;
    notifyListeners();

    try {
      // Determine doctor to book with
      DoctorModel? doctor = _assignedDoctor;
      if (doctor == null) {
        final all = await _db.getAllDoctors();
        if (all.isEmpty) {
          _addAiMsg('⚠️ No doctors are available right now. '
              'Please contact the clinic directly.');
          return;
        }
        doctor = all.first;
      }

      // Get available slots for that date
      final booked    = await _db.getBookedSlots(doctor.id, date);
      final schedule  = DoctorSchedule(doctorId: doctor.id);
      final available = schedule.allSlots.where((s) => !booked.contains(s)).toList();

      if (available.isEmpty) {
        _messages.add(ChatMessage(
          text: '😕 No slots available on ${_fmtDate(date)} with '
              'Dr. ${doctor.name}. Please choose another date.',
          isUser:             false,
          showCalendarPicker: true,
          appointmentSymptoms: _pendingSymptoms,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // Auto-book earliest available slot
      final slot = available.first;
      final appt = await _db.bookAppointment(
        doctorId:    doctor.id,
        doctorName:  doctor.name,
        patientId:   _patient!.id,
        patientName: _patient!.name,
        date:        date,
        timeSlot:    slot,
        symptoms:    _pendingSymptoms.isNotEmpty
            ? _pendingSymptoms
            : ['General consultation'],
      );

      if (appt == null) {
        // Slot was just taken — retry with next slot
        if (available.length > 1) {
          final slot2 = available[1];
          final appt2 = await _db.bookAppointment(
            doctorId:    doctor.id,
            doctorName:  doctor.name,
            patientId:   _patient!.id,
            patientName: _patient!.name,
            date:        date,
            timeSlot:    slot2,
            symptoms:    _pendingSymptoms.isNotEmpty ? _pendingSymptoms : ['General consultation'],
          );
          if (appt2 != null) {
            await _sendBookingNotifications(doctor, appt2);
            _addBookingSuccessMsg(appt2, doctor);
            _pendingSymptoms = [];
            return;
          }
        }
        _messages.add(ChatMessage(
          text: '😕 All slots on ${_fmtDate(date)} were just taken. '
              'Please pick another date.',
          isUser:             false,
          showCalendarPicker: true,
          appointmentSymptoms: _pendingSymptoms,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // ✅ Success
      await _sendBookingNotifications(doctor, appt);
      _addBookingSuccessMsg(appt, doctor);
      _pendingSymptoms = [];
    } catch (e) {
      debugPrint('❌ Booking error: $e');
      _addAiMsg('❌ Something went wrong booking your appointment. Please try again.');
    }
  }

  void _addBookingSuccessMsg(AppointmentSlot appt, DoctorModel doctor) {
    _messages.add(ChatMessage(
      text: '🎉 Appointment Booked Successfully!\n\n'
          '👨‍⚕️ Doctor: Dr. ${doctor.name}'
          '${doctor.specialization != null ? " (${doctor.specialization})" : ""}\n'
          '📅 Date: ${appt.dateLabel}\n'
          '🕐 Time: ${appt.timeSlot}\n'
          '📋 Reason: ${appt.symptoms.isNotEmpty ? appt.symptoms.join(", ") : "General consultation"}\n\n'
          'A confirmation has been sent to you. '
          'Please arrive 10 minutes early. See you then! 😊',
      isUser:  false,
      actions: ['appointment_confirmed'],
    ));
    _thinking = false;
    notifyListeners();
  }

  Future<void> _sendBookingNotifications(DoctorModel doctor, AppointmentSlot appt) async {
    // ✅ Notify PATIENT
    await NotificationService.showQueueStatusNotification(
      title: '✅ Appointment Confirmed!',
      body:  'Dr. ${doctor.name} on ${appt.dateLabel} at ${appt.timeSlot}',
    );
    await InboxService.sendAppointmentNotification(
      userId:          _patient!.id,
      doctorName:      doctor.name,
      appointmentTime: appt.date,
      appointmentId:   appt.id,
    );
    await NotificationService.sendPushToUser(
      userId:         _patient!.id,
      userCollection: 'patients',
      title:          '✅ Appointment Confirmed!',
      body:           'Dr. ${doctor.name} — ${appt.dateLabel} at ${appt.timeSlot}',
      channel:        'careloop_queue',
    );

    // ✅ Notify DOCTOR
    await _db.createDoctorInboxMessage(DoctorInboxMessage(
      id:          '',
      doctorId:    doctor.id,
      patientId:   _patient!.id,
      patientName: _patient!.name,
      message:     '📅 New appointment: ${_patient!.name} has booked '
          '${appt.dateLabel} at ${appt.timeSlot}. '
          'Reason: ${appt.symptoms.isNotEmpty ? appt.symptoms.join(", ") : "General consultation"}',
      type:        'appointment_booked',
      read:        false,
      createdAt:   DateTime.now(),
    ));
    await NotificationService.sendPushToUser(
      userId:         doctor.id,
      userCollection: 'doctors',
      title:          '📅 New Appointment — ${_patient!.name}',
      body:           '${appt.dateLabel} at ${appt.timeSlot}',
      channel:        'careloop_queue',
    );
  }

  // ── Process Gemini response ───────────────────────────────────────────────
  Future<void> _processResponse(GeminiResponse response, String userText) async {
    String           msg        = response.message;
    List<String>     finalActs  = List.from(response.actions);
    bool             showCal    = false;
    MedStatusResult? medStatus;
    DocumentAnalysis? docAnalysis;

    // ── Feature 1: Book appointment → show calendar ───────────────────────
    if (response.actions.contains('book_appointment') || response.appointmentIntent) {
      showCal          = true;
      _pendingSymptoms = response.appointmentSymptoms;
      finalActs.remove('book_appointment');

      if (!msg.contains('calendar') && !msg.contains('date') && !msg.contains('pick')) {
        msg = '$msg\n\nPlease pick a date from the calendar below — '
            'I\'ll automatically book the earliest available slot for you! 📅';
      }
    }

    // ── Feature 2: Alert doctor ───────────────────────────────────────────
    if (response.actions.contains('alert_doctor')) {
      await _handleAlertDoctor(userText, response.risk.name);
      if (!msg.contains('doctor') && !msg.contains('notif')) {
        msg = '$msg\n\n'
            '🔔 Your doctor has been notified and will review your situation. '
            'They will send advice back to you shortly.';
      }
    }

    // ── Feature 3: Check medications ──────────────────────────────────────
    if (response.actions.contains('check_medications') || response.checkMedications) {
      finalActs.remove('check_medications');
      medStatus = await _checkMedStatus();
      msg       = _buildMedStatusMsg(medStatus);

      if (medStatus != null && !medStatus.noMeds && !medStatus.allTaken) {
        // Send reminders for missed meds
        for (final med in medStatus.missed) {
          await NotificationService.showMedicationReminder(med.name, med.dosage);
          await InboxService.sendMedicationReminder(
            userId:         _patient!.id,
            medicationName: med.name,
            dosage:         med.dosage,
            medicationId:   med.id,
          );
        }
      }
    }

    // ── Feature 4: Document analysis ─────────────────────────────────────
    if (response.documentAnalysis != null) {
      docAnalysis = response.documentAnalysis;
      if (msg.isEmpty) msg = '📄 Here\'s the analysis of your document:';
    }

    // ── Agentic: join queue ───────────────────────────────────────────────
    if (response.actions.contains('join_queue')) {
      msg = await _handleQueueJoin(response);
      finalActs.remove('join_queue');
    }

    _messages.add(ChatMessage(
      text:               msg,
      isUser:             false,
      risk:               response.risk.name,
      actions:            finalActs.where((a) => a != 'alert_doctor').toList(),
      showCalendarPicker: showCal,
      appointmentSymptoms: response.appointmentSymptoms,
      documentAnalysis:   docAnalysis,
      medicationStatus:   medStatus,
    ));
    _thinking = false;
    notifyListeners();

    // Persist check-in to Firestore
    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id:               '',
        patientId:        _patient!.id,
        userMessage:      userText,
        aiResponse:       msg,
        risk:             response.risk.name,
        actionsTriggered: finalActs,
        createdAt:        DateTime.now(),
      ));
      for (final a in finalActs) await _handleOtherAction(a);
    }
  }

  // ── Feature 2: Alert doctor ───────────────────────────────────────────────
  Future<void> _handleAlertDoctor(String message, String riskLevel) async {
    if (_patient == null) return;

    // Determine doctorId — use assigned doctor first, then fallback
    String? doctorId   = _patient!.assignedDoctorId ?? _assignedDoctor?.id;
    String? doctorName = _assignedDoctor?.name;

    if (doctorId == null || doctorId.isEmpty) {
      try {
        final all = await _db.getAllDoctors();
        if (all.isNotEmpty) {
          doctorId   = all.first.id;
          doctorName = all.first.name;
        }
      } catch (_) {}
    }

    if (doctorId == null || doctorId.isEmpty) {
      // No doctor at all — just show local alert
      await NotificationService.showHealthAlert(
          '${_patient!.name} reported: $message');
      return;
    }

    // Create HealthAlert in Firestore
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

    // Push to doctor
    await NotificationService.sendPushToUser(
      userId:         doctorId,
      userCollection: 'doctors',
      title:          '🚨 Patient Alert — ${_patient!.name}',
      body:           '$message (Risk: $riskLevel) — Tap to review and send advice.',
      channel:        'careloop_alerts',
    );

    debugPrint('✅ Health alert sent to doctor $doctorId (${doctorName ?? "?"})');
  }

  // ── Feature 3: Check medication status ───────────────────────────────────
  Future<MedStatusResult?> _checkMedStatus() async {
    if (_patient == null) return null;
    try {
      final meds   = await _db.getMedicationsForPatient(_patient!.id);
      final taken  = meds.where((m) => m.isTakenToday).toList();
      final missed = meds.where((m) => m.active && !m.isTakenToday).toList();
      return MedStatusResult(all: meds, taken: taken, missed: missed);
    } catch (e) {
      debugPrint('❌ Med status check: $e');
      return null;
    }
  }

  String _buildMedStatusMsg(MedStatusResult? s) {
    if (s == null)      return '❌ Could not retrieve your medication data. Please try again.';
    if (s.noMeds)       return 'You don\'t have any medications prescribed yet. '
        'Your doctor will add medications after your consultation.';
    if (s.allTaken)     return '✅ You\'ve taken ALL your medications today! '
        'Great job — keep up the consistency!\n\n'
        '${s.all.map((m) => '✓ ${m.name} (${m.dosage})').join('\n')}';

    final missedList = s.missed.map((m) => '• ${m.name} (${m.dosage})').join('\n');
    return '⚠️ You still need to take ${s.missed.length} medication(s) today:\n\n'
        '$missedList\n\n'
        'I\'ve sent you a reminder notification! '
        'Please take them as soon as possible. 💊';
  }

  // ── Queue join ────────────────────────────────────────────────────────────
  Future<String> _handleQueueJoin(GeminiResponse r) async {
    if (_queueProvider == null || _patient == null) {
      return 'I\'d love to help you join the queue. Please use the Queue tab.';
    }
    if (_queueProvider!.isAlreadyInQueue) {
      final pos  = _queueProvider!.myPosition;
      final wait = _queueProvider!.myEstimatedWait;
      return 'You\'re already in the queue at position #$pos. '
          '${wait == 0 ? "You\'re next!" : "~$wait minutes wait."} 🏥';
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
    return '✅ Added you to the queue at position #$pos. '
        '${pos <= 1 ? "You\'re next — head to the clinic!" : "~$wait minutes estimated wait."} 🏥';
  }

  // ── Other actions ─────────────────────────────────────────────────────────
  Future<void> _handleOtherAction(String action) async {
    if (_patient == null) return;
    switch (action) {
      case 'suggest_revisit':
        await _db.createAlert(
          patientId: _patient!.id,
          type:      'revisit',
          message:   'AI suggests a revisit.',
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

  void _addAiMsg(String text) {
    _messages.add(ChatMessage(text: text, isUser: false));
    _thinking = false;
    notifyListeners();
  }

  String _fmtDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday-1]}, ${d.day} ${months[d.month-1]} ${d.year}';
  }

  void clearChat() {
    _messages.clear();
    _sessionReady    = false;
    _gemini          = GeminiService(role: GeminiRole.patient);
    _pendingSymptoms = [];
    notifyListeners();
  }
}

void debugPrint(String msg) => print(msg);