import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'appointment_provider.dart';

// ─── Chat Message ─────────────────────────────────────────────────────────────

class ChatMessage {
  final String       text;
  final bool         isUser;
  final String?      risk;
  final List<String> actions;
  final DateTime     timestamp;
  final bool         hasImage;

  /// Show inline calendar date picker
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

/// Result of medication status check
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
  GeminiService      _gemini           = GeminiService(role: GeminiRole.patient);
  final _db                            = FirestoreService();
  QueueProvider?     _queueProvider;
  AppointmentProvider? _appointmentProvider;

  final List<ChatMessage> _messages = [];
  bool             _thinking          = false;
  bool             _sessionReady      = false;
  String?          _todayQuestion;

  // Loaded from Firestore at init — injected into Gemini context
  PatientModel?    _patient;
  DoctorModel?     _assignedDoctor;
  List<Medication> _loadedMeds        = [];

  // Held while user picks a date from the calendar
  List<String>     _pendingSymptoms   = [];

  // Getters
  List<ChatMessage>  get messages      => _messages;
  bool               get thinking      => _thinking;
  bool               get sessionReady  => _sessionReady;
  String?            get todayQuestion => _todayQuestion;
  PatientModel?      get patient       => _patient;

  void setQueueProvider(QueueProvider qp) => _queueProvider = qp;
  void setAppointmentProvider(AppointmentProvider ap) => _appointmentProvider = ap;

  // ── Session init ──────────────────────────────────────────────────────────
  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;

    // 1. Load medications
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

    // 3. If still no doctor but has meds, try to find doctor
    if (_assignedDoctor == null && _loadedMeds.isNotEmpty) {
      try {
        final doctors = await _db.getAllDoctors();
        if (doctors.isNotEmpty) _assignedDoctor = doctors.first;
      } catch (_) {}
    }

    // 4. Build med names for Gemini context
    final medNames = _loadedMeds
        .map((m) => '${m.name} ${m.dosage} (${m.frequency})')
        .toList();

    // 5. Init Gemini — errors are non-fatal (fallback still works)
    try {
      await _gemini.initSession(
        name:               patient.name,
        diagnosis:          patient.diagnosis ?? 'General',
        daysSinceVisit:     patient.daysSinceVisit,
        medications:        medNames,
        assignedDoctorName: _assignedDoctor?.name,
      );
    } catch (e) {
      debugPrint('⚠️ Gemini init: $e');
    }

    // 6. Generate check-in question
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
    await _processResponse(response, text, isImageScan: false);
  }

  // ── Send with image (Issue 1+2 fix) ──────────────────────────────────────
  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    // Issue 1 fix: show a clear user message and AI pre-response
    final display = text.isEmpty ? '📄 Please scan and summarise this document for me.' : text;
    _messages.add(ChatMessage(text: display, isUser: true, hasImage: true));

    // Show a pending "scanning" message immediately so user knows what's happening
    _messages.add(ChatMessage(
      text: '📄 Sure! I\'m scanning your document now — I\'ll give you a clear summary in just a moment...',
      isUser: false,
    ));
    _thinking = true;
    notifyListeners();

    // Build explicit scan prompt — forces Gemini into document_analysis path
    final scanPrompt = text.isEmpty
        ? 'Please analyse this medication bill / prescription / medical report / document image. '
        'Provide a clear and easy-to-understand structured breakdown. '
        'Include all medication names, dosages, prices, instructions, and any important notes.'
        : text;

    final response = await _gemini.sendMessageWithImage(
        scanPrompt, imageBytes, mimeType);

    // Remove the pending "scanning" message before showing real response
    if (_messages.isNotEmpty && !_messages.last.isUser &&
        _messages.last.text.contains('scanning your document')) {
      _messages.removeLast();
    }

    await _processResponse(response, scanPrompt, isImageScan: true);
  }

  // ── Feature 1: Date selected from calendar ────────────────────────────────
  Future<void> onDateSelected(DateTime date) async {
    if (_patient == null) return;

    _messages.add(ChatMessage(
      text:   '📅 I\'d like to book on ${_fmtDate(date)}',
      isUser: true,
    ));
    _thinking = true;
    notifyListeners();

    try {
      DoctorModel? doctor = _assignedDoctor;
      if (doctor == null) {
        final all = await _db.getAllDoctors();
        if (all.isEmpty) {
          _addAiMsg('⚠️ No doctors are available right now. Please contact the clinic directly.');
          return;
        }
        doctor = all.first;
      }

      final booked    = await _db.getBookedSlots(doctor.id, date);
      final schedule  = DoctorSchedule(doctorId: doctor.id);
      final available = schedule.allSlots.where((s) => !booked.contains(s)).toList();

      if (available.isEmpty) {
        _messages.add(ChatMessage(
          text: '😕 No slots available on ${_fmtDate(date)} with Dr. ${doctor.name}. '
              'Please choose another date.',
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
        // Slot race condition — retry with next
        if (available.length > 1) {
          final appt2 = await _db.bookAppointment(
            doctorId:    doctor.id,
            doctorName:  doctor.name,
            patientId:   _patient!.id,
            patientName: _patient!.name,
            date:        date,
            timeSlot:    available[1],
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
          text: '😕 All slots on ${_fmtDate(date)} were just taken. Please pick another date.',
          isUser:             false,
          showCalendarPicker: true,
          appointmentSymptoms: _pendingSymptoms,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // Issue 5+6 fix: refresh AppointmentProvider so new booking appears in dashboard
      _appointmentProvider?.startListening(_patient!.id);

      await _sendBookingNotifications(doctor, appt);
      _addBookingSuccessMsg(appt, doctor);
      _pendingSymptoms = [];
    } catch (e) {
      debugPrint('❌ Booking error: $e');
      _addAiMsg('❌ Something went wrong booking your appointment. Please try again.');
    }
  }

  void _addBookingSuccessMsg(AppointmentSlot appt, DoctorModel doctor) {
    // Fix null safety: check if symptoms is not null before accessing isNotEmpty
    final symptomsText = (appt.symptoms?.isNotEmpty ?? false)
        ? appt.symptoms!.join(", ")
        : "General consultation";

    _messages.add(ChatMessage(
      text: '🎉 Appointment Booked Successfully!\n\n'
          '👨‍⚕️ Doctor: Dr. ${doctor.name}'
          '${doctor.specialization != null ? " (${doctor.specialization})" : ""}\n'
          '📅 Date: ${appt.dateLabel}\n'
          '🕐 Time: ${appt.timeSlot}\n'
          '📋 Reason: $symptomsText\n\n'
          'A confirmation has been sent to you. Please arrive 10 minutes early. 😊',
      isUser:  false,
      actions: ['appointment_confirmed'],
    ));
    _thinking = false;
    notifyListeners();
  }

  Future<void> _sendBookingNotifications(DoctorModel doctor, AppointmentSlot appt) async {
    // Fix null safety: check if symptoms is not null before accessing isNotEmpty
    final symptomsText = (appt.symptoms?.isNotEmpty ?? false)
        ? appt.symptoms!.join(", ")
        : "General consultation";

    // Notify PATIENT
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

    // Notify DOCTOR
    await _db.createDoctorInboxMessage(DoctorInboxMessage(
      id:          '',
      doctorId:    doctor.id,
      patientId:   _patient!.id,
      patientName: _patient!.name,
      message:     '📅 New appointment: ${_patient!.name} booked '
          '${appt.dateLabel} at ${appt.timeSlot}. '
          'Reason: $symptomsText',
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
  Future<void> _processResponse(
      GeminiResponse response,
      String userText, {
        bool isImageScan = false,
      }) async {
    String            msg        = response.message;
    List<String>      finalActs  = List.from(response.actions);
    bool              showCal    = false;
    MedStatusResult?  medStatus;
    DocumentAnalysis? docAnalysis;

    // ── Issue 2 fix: Document scan takes full priority — skip ALL other actions ──
    if (isImageScan || response.documentAnalysis != null) {
      docAnalysis = response.documentAnalysis;

      // Build a good message if Gemini gave a short one
      if (msg.isEmpty || msg == 'Received.' || msg == 'Update received.') {
        msg = docAnalysis != null
            ? '📄 Here\'s the analysis of your document:'
            : '📄 I\'ve reviewed your document. Here\'s what I found:';
      }

      // Issue 2 fix: NO calendar, NO alert, NO other logic when scanning
      _messages.add(ChatMessage(
        text:             msg,
        isUser:           false,
        risk:             'low',
        actions:          const [],
        documentAnalysis: docAnalysis,
      ));
      _thinking = false;
      notifyListeners();

      // Save check-in but with no actions
      if (_patient != null) {
        await _db.saveCheckIn(CheckIn(
          id: '', patientId: _patient!.id,
          userMessage: userText, aiResponse: msg,
          risk: 'low', actionsTriggered: [],
          createdAt: DateTime.now(),
        ));
      }
      return; // Early return — document scan is complete
    }

    // ── Issue 4 fix: Medication check — NO calendar, skip appointment logic ──
    final isMedCheck = response.actions.contains('check_medications') ||
        response.checkMedications;

    if (isMedCheck) {
      // Remove any appointment-related entries so calendar doesn't appear
      finalActs.remove('check_medications');
      finalActs.remove('book_appointment');
      showCal = false; // Explicitly prevent calendar

      medStatus = await _checkMedStatus();
      msg       = _buildMedStatusMsg(medStatus);

      if (medStatus != null && !medStatus.noMeds && !medStatus.allTaken) {
        for (final med in medStatus.missed) {
          await NotificationService.showMedicationReminder(med.name, med.dosage);
          if (_patient != null) {
            await InboxService.sendMedicationReminder(
              userId:         _patient!.id,
              medicationName: med.name,
              dosage:         med.dosage,
              medicationId:   med.id,
            );
          }
        }
      }

      _messages.add(ChatMessage(
        text:             msg,
        isUser:           false,
        risk:             'low',
        actions:          finalActs,
        medicationStatus: medStatus,
        showCalendarPicker: false, // Explicitly false
      ));
      _thinking = false;
      notifyListeners();

      if (_patient != null) {
        await _db.saveCheckIn(CheckIn(
          id: '', patientId: _patient!.id,
          userMessage: userText, aiResponse: msg,
          risk: 'low', actionsTriggered: [],
          createdAt: DateTime.now(),
        ));
      }
      return; // Early return
    }

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
    ));
    _thinking = false;
    notifyListeners();

    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id: '', patientId: _patient!.id,
        userMessage: userText, aiResponse: msg,
        risk: response.risk.name, actionsTriggered: finalActs,
        createdAt: DateTime.now(),
      ));
      for (final a in finalActs) await _handleOtherAction(a);
    }
  }

  // ── Feature 2: Alert doctor ───────────────────────────────────────────────
  Future<void> _handleAlertDoctor(String message, String riskLevel) async {
    if (_patient == null) return;

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
      await NotificationService.showHealthAlert(
          '${_patient!.name} reported: $message');
      return;
    }

    final alert = HealthAlert(
      id: '', patientId: _patient!.id, patientName: _patient!.name,
      doctorId: doctorId, message: message, riskLevel: riskLevel,
      status: 'pending', createdAt: DateTime.now(),
    );
    await _db.createHealthAlert(alert);

    await NotificationService.sendPushToUser(
      userId:         doctorId,
      userCollection: 'doctors',
      title:          '🚨 Patient Alert — ${_patient!.name}',
      body:           '$message (Risk: $riskLevel) — Tap to review and send advice.',
      channel:        'careloop_alerts',
    );
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
    if (s == null)  return '❌ Could not retrieve your medication data. Please try again.';
    if (s.noMeds)   return 'You don\'t have any medications prescribed yet. '
        'Your doctor will add medications after your consultation.';
    if (s.allTaken) return '✅ You\'ve taken ALL your medications today! '
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
        '${pos <= 1 ? "You\'re next — head to the clinic!" : "~$wait minutes wait."} 🏥';
  }

  // ── Other actions ─────────────────────────────────────────────────────────
  Future<void> _handleOtherAction(String action) async {
    if (_patient == null) return;
    switch (action) {
      case 'suggest_revisit':
        await _db.createAlert(
          patientId: _patient!.id, type: 'revisit',
          message: 'AI suggests a revisit.',
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
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
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