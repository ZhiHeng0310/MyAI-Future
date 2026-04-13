import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api_service.dart';
import '../models/checkin_model.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/appointment_model.dart' hide HealthAlert;
import '../models/medication_model.dart';
import '../models/health_alert_model.dart' hide DoctorInboxMessage;
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';
import 'queue_provider.dart';
import 'appointment_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CHAT MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════════════

class ChatMessage {
  final String text;
  final bool isUser;
  final String? risk;
  final List<String> actions;
  final DateTime timestamp;
  final bool hasImage;

  // Step 1 – show date calendar
  final bool showCalendarPicker;
  final List<String> appointmentSymptoms;

  // Step 2 – show time slots for the chosen date
  final bool showTimeSlotPicker;
  final DateTime? slotDate;
  final List<String> availableSlots;
  final DoctorModel? slotDoctor;

  final DocumentAnalysis? documentAnalysis;
  final MedStatusResult? medicationStatus;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions = const [],
    DateTime? timestamp,
    this.hasImage = false,
    this.showCalendarPicker = false,
    this.appointmentSymptoms = const [],
    this.showTimeSlotPicker = false,
    this.slotDate,
    this.availableSlots = const [],
    this.slotDoctor,
    this.documentAnalysis,
    this.medicationStatus,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Medication Check Result
class MedStatusResult {
  final List<Medication> all;
  final List<Medication> taken;
  final List<Medication> missed;
  final List<Medication> upcoming;
  final Medication? nextMedication;
  final String? nextMedicationTime;
  final int takenSlots;
  final int totalSlots;

  const MedStatusResult({
    required this.all,
    required this.taken,
    required this.missed,
    required this.upcoming,
    this.nextMedication,
    this.nextMedicationTime,
    required this.takenSlots,
    required this.totalSlots,
  });

  /// True only when every scheduled dose has been taken today and none missed
  bool get allTaken =>
      totalSlots > 0 &&
          missed.isEmpty &&
          takenSlots == totalSlots;
  bool get noMeds => all.isEmpty;
  double get adherenceRate =>
      totalSlots == 0 ? 1.0 : takenSlots / totalSlots;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class ChatProvider extends ChangeNotifier {
  GeminiService _gemini = GeminiService(role: GeminiRole.patient);
  final _db = FirestoreService();
  QueueProvider? _queueProvider;
  AppointmentProvider? _appointmentProvider;

  final List<ChatMessage> _messages = [];
  bool _thinking = false;
  bool _sessionReady = false;
  String? _todayQuestion;

  PatientModel? _patient;
  List<DoctorModel> _prescribingDoctors = [];
  List<Medication> _loadedMeds = [];
  List<String> _pendingSymptoms = [];

  List<ChatMessage> get messages => _messages;
  bool get thinking => _thinking;
  bool get sessionReady => _sessionReady;
  String? get todayQuestion => _todayQuestion;
  PatientModel? get patient => _patient;

  void setQueueProvider(QueueProvider qp) => _queueProvider = qp;
  void setAppointmentProvider(AppointmentProvider ap) =>
      _appointmentProvider = ap;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;

    try {
      _loadedMeds = await _db.getMedicationsForPatient(patient.id);
    } catch (_) {
      _loadedMeds = [];
    }

    _prescribingDoctors = await _getPrescribingDoctors(_loadedMeds);

    final medNames = _loadedMeds
        .map((m) => '${m.name} ${m.dosage} (${m.frequency})')
        .toList();
    final doctorNames = _prescribingDoctors.map((d) => d.name).toList();

    try {
      await _gemini.initSession(
        name: patient.name,
        diagnosis: patient.diagnosis ?? 'General',
        daysSinceVisit: patient.daysSinceVisit,
        medications: medNames,
        prescribingDoctors: doctorNames,
      );
    } catch (e) {
      debugPrint('⚠️ Gemini init: $e');
    }

    _todayQuestion = await _gemini.generateCheckInQuestion(
        patient.diagnosis ?? 'General', patient.daysSinceVisit);

    _sessionReady = true;

    final firstName = patient.name.split(' ').first;
    final medNote = _loadedMeds.isEmpty
        ? ''
        : '\n\nYou have ${_loadedMeds.length} medication(s) prescribed. '
        'Ask me to check if you\'ve taken them today!';
    final doctorNote = _prescribingDoctors.isEmpty
        ? '\n\nNo doctors have prescribed medications to you yet.'
        : '\n\nYour prescribing doctors: ${doctorNames.join(', ')}';

    _messages.add(ChatMessage(
      text: 'Hi $firstName! 👋 I\'m CareLoop AI. '
          '${_todayQuestion ?? "How are you feeling today?"}'
          '$medNote'
          '$doctorNote\n\n'
          'I can:\n'
          '📅 Book appointments\n'
          '💊 Check your medications\n'
          '🚨 Alert your doctors if you feel unwell\n'
          '📄 Scan medication bills',
      isUser: false,
    ));
    notifyListeners();
  }

  Future<List<DoctorModel>> _getPrescribingDoctors(
      List<Medication> meds) async {
    final doctorIds = meds
        .map((m) => m.doctorId)
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    final doctors = <DoctorModel>[];
    for (final id in doctorIds) {
      try {
        final doctor = await _db.getDoctor(id!);
        if (doctor != null) doctors.add(doctor);
      } catch (_) {}
    }
    return doctors;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MESSAGE HANDLING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(
      text: text,
      isUser: true,
    ));

    _thinking = true;
    notifyListeners();

    try {
      // Build conversation history
      final conversationHistory = _messages
          .where((m) => m != _messages.last)
          .map((m) => {
        "role": m.isUser ? "user" : "assistant",
        "content": m.text,
      })
          .toList();

      // ✅ CORRECT API CALL
      final res = await ApiService.sendChat(
        message: text,
        role: 'patient',
        userId: _patient?.id,
        conversationHistory: conversationHistory,
      );

      final message = res['message'] ?? 'No response';
      final actions = List<String>.from(res['actions'] ?? []);
      final risk = res['risk'] ?? 'low';
      final feelUnwell = res['feel_unwell'] ?? false;
      final unwellSymptoms = List<String>.from(res['unwell_symptoms'] ?? []);

      // ✅ FIX 1: map appointment_intent OR actions containing book_appointment → show calendar
      final appointmentIntent = res['appointment_intent'] ?? false;
      final showCalendar = (appointmentIntent == true) ||
          actions.contains('book_appointment');
      final appointmentSymptoms =
      List<String>.from(res['appointmentSymptoms'] ?? []);
      if (showCalendar) _pendingSymptoms = appointmentSymptoms;

      // ✅ FIX 2: check_medications from response → trigger real medication check
      final checkMeds = res['check_medications'] ?? false;
      if ((checkMeds == true) || actions.contains('check_medications')) {
        final medStatus = await _checkMedicationStatus();
        final medMsg = _buildMedicationStatusMessage(medStatus);

        // Fire reminders for missed medications
        if (medStatus != null && !medStatus.noMeds && !medStatus.allTaken) {
          for (final med in medStatus.missed) {
            for (final time in med.reminderTimes) {
              await NotificationService.showReminder(
                  med.name, med.dosage, time);
              if (_patient != null) {
                await InboxService.sendReminder(
                  userId: _patient!.id,
                  medicationName: med.name,
                  dosage: med.dosage,
                  scheduledTime: time,
                  medicationId: med.id,
                );
              }
            }
          }
        }

        _messages.add(ChatMessage(
          text: medMsg,
          isUser: false,
          risk: 'low',
          actions: const [],
          medicationStatus: medStatus,
        ));
        _thinking = false;
        notifyListeners();

        // Save check-in to Firebase
        if (_patient != null) {
          await _db.saveCheckIn(CheckIn(
            id: '',
            patientId: _patient!.id,
            userMessage: text,
            aiResponse: medMsg,
            risk: 'low',
            actionsTriggered: [],
            createdAt: DateTime.now(),
          ));
        }
        return;
      }

      // ✅ FIX 3: open_image_picker action — just show the message; UI handles the action chip
      final cleanedActions = actions.where((a) => a != 'book_appointment').toList();

      // Handle feel unwell
      if (feelUnwell && unwellSymptoms.isNotEmpty) {
        await _handleFeelUnwell(text, unwellSymptoms, risk);
      }

      _messages.add(ChatMessage(
        text: message,
        isUser: false,
        actions: cleanedActions,
        risk: risk,
        showCalendarPicker: showCalendar,
        appointmentSymptoms: appointmentSymptoms,
      ));

      // Save check-in to Firebase
      if (_patient != null) {
        try {
          await _db.saveCheckIn(CheckIn(
            id: '',
            patientId: _patient!.id,
            userMessage: text,
            aiResponse: message,
            risk: risk,
            actionsTriggered: cleanedActions,
            createdAt: DateTime.now(),
          ));
        } catch (saveErr) {
          debugPrint('⚠️ Check-in save failed (non-fatal): $saveErr');
        }
      }
    } catch (e) {
      _messages.add(ChatMessage(
        text: "❌ Connection error: ${e.toString()}\n\nPlease check:\n1. Internet connection\n2. Backend is running\n3. Try again in a moment",
        isUser: false,
      ));
    }

    _thinking = false;
    notifyListeners();
  }

  Future<void> sendMessageWithImage(
      String text,
      Uint8List imageBytes,
      String mimeType,
      ) async {
    _messages.add(ChatMessage(
      text: text.isEmpty
          ? '📄 Scanning document...'
          : text,
      isUser: true,
      hasImage: true,
    ));

    _thinking = true;
    notifyListeners();

    try {
      final res = await ApiService.sendImageChat(
        message: text,
        imageBytes: imageBytes,
        mimeType: mimeType,
        patientId: _patient?.id,
      );

      _messages.add(ChatMessage(
        text: res['message'] ?? 'No response',
        isUser: false,
        documentAnalysis: res['documentAnalysis'],
      ));
    } catch (e) {
      _messages.add(ChatMessage(
        text: "❌ Image processing failed: $e",
        isUser: false,
      ));
    }

    _thinking = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 1 — User picks a DATE from the calendar
  // Load available slots for that date and show them
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> onDateSelected(DateTime date) async {
    if (_patient == null) return;

    // Add user message showing chosen date
    _messages.add(ChatMessage(
      text: '📅 I\'d like to book on ${_fmtDate(date)}',
      isUser: true,
    ));
    _thinking = true;
    notifyListeners();

    try {
      // Resolve doctor
      DoctorModel? doctor = _prescribingDoctors.isNotEmpty
          ? _prescribingDoctors.first
          : null;

      if (doctor == null) {
        final all = await _db.getAllDoctors();
        if (all.isEmpty) {
          _addAiMsg('⚠️ No doctors are available. Please contact the clinic.');
          return;
        }
        doctor = all.first;
      }

      // Fetch booked slots and compute available ones
      final booked = await _db.getBookedSlots(doctor.id, date);
      final schedule = DoctorSchedule(doctorId: doctor.id);
      final available =
      schedule.allSlots.where((s) => !booked.contains(s)).toList();

      if (available.isEmpty) {
        // No slots on this day — keep calendar open so user picks another date
        _messages.add(ChatMessage(
          text: '😕 No slots available on ${_fmtDate(date)} with Dr. ${doctor.name}. '
              'Please choose another date.',
          isUser: false,
          showCalendarPicker: true,
          appointmentSymptoms: _pendingSymptoms,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      // ✅ Show time slots so user can pick one
      _messages.add(ChatMessage(
        text: '🕐 Available slots on ${_fmtDate(date)} with Dr. ${doctor.name}.\n'
            'Please pick a time:',
        isUser: false,
        showTimeSlotPicker: true,
        slotDate: date,
        availableSlots: available,
        slotDoctor: doctor,
        appointmentSymptoms: _pendingSymptoms,
      ));
      _thinking = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Date selection error: $e');
      _addAiMsg('❌ Could not load available slots. Please try again.');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 2 — User picks a TIME SLOT → actually book
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> onTimeSlotSelected(
      DateTime date, String timeSlot, DoctorModel doctor) async {
    if (_patient == null) return;

    // Add user message showing chosen slot
    _messages.add(ChatMessage(
      text: '🕐 I\'ll take the ${timeSlot} slot on ${_fmtDate(date)}',
      isUser: true,
    ));
    _thinking = true;
    notifyListeners();

    try {
      final appt = await _db.bookAppointment(
        doctorId: doctor.id,
        doctorName: doctor.name,
        patientId: _patient!.id,
        patientName: _patient!.name,
        date: date,
        timeSlot: timeSlot,
        symptoms: _pendingSymptoms.isNotEmpty
            ? _pendingSymptoms
            : ['General consultation'],
      );

      if (appt == null) {
        // Slot was just taken by someone else — reload slots
        _addAiMsg(
            '😕 That slot was just taken. Please pick another time.');
        // Re-show the slot picker with fresh data
        final booked = await _db.getBookedSlots(doctor.id, date);
        final schedule = DoctorSchedule(doctorId: doctor.id);
        final available =
        schedule.allSlots.where((s) => !booked.contains(s)).toList();

        if (available.isEmpty) {
          _messages.add(ChatMessage(
            text: '😕 No more slots on ${_fmtDate(date)}. Please pick another date.',
            isUser: false,
            showCalendarPicker: true,
            appointmentSymptoms: _pendingSymptoms,
          ));
        } else {
          _messages.add(ChatMessage(
            text: '🕐 Remaining slots on ${_fmtDate(date)} with Dr. ${doctor.name}:',
            isUser: false,
            showTimeSlotPicker: true,
            slotDate: date,
            availableSlots: available,
            slotDoctor: doctor,
            appointmentSymptoms: _pendingSymptoms,
          ));
        }
        _thinking = false;
        notifyListeners();
        return;
      }

      // ✅ Booking successful

      // 1. Refresh appointment provider so the Appointments tab updates immediately
      _appointmentProvider?.startListening(_patient!.id);

      // 2. Send notifications to both patient and doctor
      await _sendAppointmentNotifications(doctor, appt);

      // 3. Show success message in chat
      _addBookingSuccessMsg(appt, doctor);

      // 4. Clear pending symptoms
      _pendingSymptoms = [];
    } catch (e) {
      debugPrint('❌ Booking error: $e');
      _addAiMsg('❌ Something went wrong booking that slot. Please try again.');
    }
  }

  void _addBookingSuccessMsg(AppointmentSlot appt, DoctorModel doctor) {
    final symptomsText = appt.symptoms.isNotEmpty
        ? appt.symptoms.join(", ")
        : "General consultation";

    _messages.add(ChatMessage(
      text: '🎉 Appointment Booked Successfully!\n\n'
          '👨‍⚕️ Doctor: Dr. ${doctor.name}'
          '${doctor.specialization != null ? " (${doctor.specialization})" : ""}\n'
          '📅 Date: ${appt.dateLabel}\n'
          '🕐 Time: ${appt.timeSlot}\n'
          '📋 Reason: $symptomsText\n\n'
          'You can check your appointment in the 📅 Appointments tab. '
          'Please arrive 10 minutes early. 😊',
      isUser: false,
      actions: ['appointment_confirmed'],
    ));
    _thinking = false;
    notifyListeners();
  }

  /// Send notifications to BOTH patient and doctor
  Future<void> _sendAppointmentNotifications(
      DoctorModel doctor, AppointmentSlot appt) async {
    final symptomsText = appt.symptoms.isNotEmpty
        ? appt.symptoms.join(", ")
        : "General consultation";

    // ── Notify PATIENT ──────────────────────────────────────────────────────
    // OS notification (immediate)
    await NotificationService.showQueueStatusNotification(
      title: '✅ Appointment Confirmed!',
      body: 'Dr. ${doctor.name} on ${appt.dateLabel} at ${appt.timeSlot}',
    );
    // Inbox notification (persistent, shows in notification bell)
    await InboxService.sendAppointmentNotification(
      userId: _patient!.id,
      doctorName: doctor.name,
      appointmentTime: appt.date,
      appointmentId: appt.id,
    );
    // FCM push (works when app is closed/background)
    await NotificationService.sendPushToUser(
      userId: _patient!.id,
      userCollection: 'patients',
      title: '✅ Appointment Confirmed!',
      body: 'Dr. ${doctor.name} — ${appt.dateLabel} at ${appt.timeSlot}',
      channel: 'careloop_queue',
    );

    // ── Notify DOCTOR ───────────────────────────────────────────────────────
    // Doctor inbox message
    await _db.createDoctorInboxMessage(DoctorInboxMessage(
      id: '',
      doctorId: doctor.id,
      patientId: _patient!.id,
      patientName: _patient!.name,
      message: '📅 New appointment: ${_patient!.name} booked '
          '${appt.dateLabel} at ${appt.timeSlot}. '
          'Reason: $symptomsText',
      type: 'appointment_booked',
      alertId: null,
      read: false,
      createdAt: DateTime.now(),
    ));
    // Doctor FCM push
    await NotificationService.sendPushToUser(
      userId: doctor.id,
      userCollection: 'doctors',
      title: '📅 New Appointment — ${_patient!.name}',
      body: '${appt.dateLabel} at ${appt.timeSlot} · $symptomsText',
      channel: 'careloop_queue',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROCESS GEMINI RESPONSE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _processResponse(
      GeminiResponse response,
      String userText, {
        bool isImageScan = false,
      }) async {
    String msg = response.message;
    List<String> finalActs = List.from(response.actions);
    bool showCal = false;
    MedStatusResult? medStatus;
    DocumentAnalysis? docAnalysis;

    // ── FEATURE 4: SCAN BILLS ───────────────────────────────────────────────
    if (isImageScan || response.documentAnalysis != null) {
      docAnalysis = response.documentAnalysis;
      if (msg.isEmpty || msg.length < 20) {
        msg = '📄 Here\'s a clear summary of your medication bill:';
      }
      _messages.add(ChatMessage(
        text: msg,
        isUser: false,
        risk: 'low',
        actions: const [],
        documentAnalysis: docAnalysis,
      ));
      _thinking = false;
      notifyListeners();
      if (_patient != null) {
        await _db.saveCheckIn(CheckIn(
          id: '',
          patientId: _patient!.id,
          userMessage: userText,
          aiResponse: msg,
          risk: 'low',
          actionsTriggered: [],
          createdAt: DateTime.now(),
        ));
      }
      return;
    }

    // ── FEATURE 1: MEDICATION CHECK ─────────────────────────────────────────
    if (response.checkMedications || finalActs.contains('check_medications')) {
      finalActs.remove('check_medications');

      medStatus = await _checkMedicationStatus();
      msg = _buildMedicationStatusMessage(medStatus);

      // Agentic: fire reminders for each missed medication
      if (medStatus != null && !medStatus.noMeds && !medStatus.allTaken) {
        for (final med in medStatus.missed) {

          for (final time in med.reminderTimes) {
            await NotificationService.showReminder(
              med.name,
              med.dosage,
              time,
            );

            if (_patient != null) {
              await InboxService.sendReminder(
                userId: _patient!.id,
                medicationName: med.name,
                dosage: med.dosage,
                scheduledTime: time,
                medicationId: med.id,
              );
            }
          }
        }
      }

      _messages.add(ChatMessage(
        text: msg,
        isUser: false,
        risk: 'low',
        actions: finalActs,
        medicationStatus: medStatus,
      ));
      _thinking = false;
      notifyListeners();
      if (_patient != null) {
        await _db.saveCheckIn(CheckIn(
          id: '',
          patientId: _patient!.id,
          userMessage: userText,
          aiResponse: msg,
          risk: 'low',
          actionsTriggered: [],
          createdAt: DateTime.now(),
        ));
      }
      return;
    }

    // ── FEATURE 3: I FEEL UNWELL ────────────────────────────────────────────
    if (response.feelUnwell || finalActs.contains('alert_all_doctors')) {
      await _handleFeelUnwell(
          userText, response.unwellSymptoms, response.risk.name);
      if (!msg.contains('doctor') && !msg.contains('alert')) {
        msg = '$msg\n\n'
            '🔔 I\'ve notified ALL your prescribing doctors about your symptoms. '
            'They will review and send advice back to you shortly.';
      }
    }

    // ── FEATURE 2: BOOK APPOINTMENT — show date calendar first ─────────────
    if (response.appointmentIntent || finalActs.contains('book_appointment')) {
      showCal = true;
      _pendingSymptoms = response.appointmentSymptoms;
      finalActs.remove('book_appointment');
      if (!msg.contains('calendar') && !msg.contains('date')) {
        msg = '$msg\n\nPlease pick a date from the calendar below — '
            'I\'ll show you the available time slots! 📅';
      }
    }

    _messages.add(ChatMessage(
      text: msg,
      isUser: false,
      risk: response.risk.name,
      actions: finalActs,
      showCalendarPicker: showCal,
      appointmentSymptoms: response.appointmentSymptoms,
    ));
    _thinking = false;
    notifyListeners();

    if (_patient != null) {
      await _db.saveCheckIn(CheckIn(
        id: '',
        patientId: _patient!.id,
        userMessage: userText,
        aiResponse: msg,
        risk: response.risk.name,
        actionsTriggered: finalActs,
        createdAt: DateTime.now(),
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MEDICATION CHECK — uses actual reminderTimes from Firestore
  // ══════════════════════════════════════════════════════════════════════════

  Future<MedStatusResult?> _checkMedicationStatus() async {
    if (_patient == null) return null;
    try {
      final meds = await _db.getMedicationsForPatient(_patient!.id);
      final now = DateTime.now();
      final taken = <Medication>[];
      final missed = <Medication>[];
      final upcoming = <Medication>[];
      Medication? nextMed;
      String? nextMedTime;

      for (final med in meds) {
        if (!med.active) continue;

        if (med.reminderTimes.isEmpty) {
          if (med.isTakenToday) {
            taken.add(med);
          } else {
            missed.add(med);
          }
          continue;
        }

        bool medHasMissed = false;
        bool medHasUpcoming = false;
        final slotStatus = <bool>[];
        String? firstUpcomingTime;

        for (final timeStr in med.reminderTimes) {
          final parts = timeStr.split(':');
          if (parts.length < 2) continue;
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;

          final scheduledTime =
          DateTime(now.year, now.month, now.day, hour, minute);
          final slotTaken = med.isTakenForSlot(timeStr);
          slotStatus.add(slotTaken);

          if (now.isAfter(scheduledTime)) {
            if (!slotTaken) {
              medHasMissed = true;
            }
          } else {
            medHasUpcoming = true;
            firstUpcomingTime ??= timeStr;
          }
        }

        final medFullyTaken = slotStatus.isNotEmpty && slotStatus.every((t) => t);
        if (medFullyTaken) {
          if (!taken.contains(med)) taken.add(med);
        }
        if (medHasMissed) {
          if (!missed.contains(med)) missed.add(med);
        }
        if (medHasUpcoming) {
          if (!upcoming.contains(med)) upcoming.add(med);
          if (firstUpcomingTime != null && nextMed == null) {
            nextMed = med;
            nextMedTime = firstUpcomingTime;
          }
        }
      }

      return MedStatusResult(
        all: meds,
        taken: taken,
        missed: missed,
        upcoming: upcoming,
        nextMedication: nextMed,
        nextMedicationTime: nextMedTime,
        takenSlots: meds.fold(0, (sum, med) => sum + med.takenSlotsToday),
        totalSlots: meds.fold(0, (sum, med) => sum + med.totalSlotsToday),
      );
    } catch (e) {
      debugPrint('❌ Med status check: $e');
      return null;
    }
  }

  String _buildMedicationStatusMessage(MedStatusResult? s) {
    if (s == null) return '❌ Could not retrieve your medication data. Please try again.';
    if (s.noMeds) {
      return 'You don\'t have any medications prescribed yet. '
          'Your doctor will prescribe medications after your consultation.';
    }
    if (s.allTaken) {
      return '✅ You\'re all up to date! You\'ve taken all your medications today.\n\n'
          '${s.all.map((m) => '✓ ${m.name} (${m.dosage})').join('\n')}\n\n'
          'Great job keeping up with your medication schedule! 💊';
    }
    final untaken =
    s.all.where((m) => !s.taken.any((t) => t.id == m.id)).toList();

    if (untaken.isNotEmpty) {
      final list = untaken
          .map((m) => '⚠️ ${m.name} (${m.dosage}) - ${m.frequency}')
          .join('\n');

      return '⚠️ You haven\'t taken ${untaken.length} medication(s) yet:\n\n'
          '$list\n\n'
          'Please remember to take them according to schedule. 💊';
    }

    if (s.nextMedication != null && s.nextMedicationTime != null) {
      final next = s.nextMedication!;
      return '📋 Your next upcoming medication:\n\n'
          '💊 ${next.name} (${next.dosage})\n'
          '🕐 Time: ${s.nextMedicationTime}\n'
          '📝 Frequency: ${next.frequency}\n\n'
          'I\'ll remind you when it\'s time to take it!';
    }
    if (s.upcoming.isNotEmpty) {
      return '📋 All your scheduled medications for today are upcoming — nothing missed yet! ✅\n\n'
          '${s.upcoming.map((m) => '⏰ ${m.name} (${m.dosage}) — ${m.reminderTimes.join(', ')}').join('\n')}';
    }
    return 'All medications are on schedule! ✅';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // I FEEL UNWELL — alert ALL prescribing doctors
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleFeelUnwell(
      String message, List<String> symptoms, String riskLevel) async {
    if (_patient == null) return;

    if (_prescribingDoctors.isEmpty) {
      try {
        final all = await _db.getAllDoctors();
        if (all.isNotEmpty) _prescribingDoctors = [all.first];
      } catch (_) {}
    }

    if (_prescribingDoctors.isEmpty) {
      await NotificationService.showHealthAlert(
          '${_patient!.name} reported: $message');
      return;
    }

    for (final doctor in _prescribingDoctors) {
      try {
        final alert = HealthAlert(
          id: '',
          patientId: _patient!.id,
          patientName: _patient!.name,
          doctorId: doctor.id,
          message: message,
          riskLevel: riskLevel,
          status: 'pending',
          createdAt: DateTime.now(),
        );
        await _db.createHealthAlert(alert);

        await NotificationService.sendPushToUser(
          userId: doctor.id,
          userCollection: 'doctors',
          title: '🚨 Patient Alert — ${_patient!.name}',
          body: '$message (Risk: $riskLevel)',
          channel: 'careloop_alerts',
        );

        await _db.createDoctorInboxMessage(DoctorInboxMessage(
          id: '',
          doctorId: doctor.id,
          patientId: _patient!.id,
          patientName: _patient!.name,
          message: '🚨 Health Alert: ${_patient!.name} reports: $message',
          type: 'health_alert',
          alertId: null,
          read: false,
          createdAt: DateTime.now(),
        ));

        debugPrint('✅ Sent health alert to Dr. ${doctor.name}');
      } catch (e) {
        debugPrint('❌ Failed to alert Dr. ${doctor.name}: $e');
      }
    }

    // Let patient know the alert was sent
    await InboxService.sendDoctorMessage(
      userId: _patient!.id,
      doctorName: 'CareLoop AI',
      message:
      '🔔 Your health alert has been sent to your doctor(s). They will respond shortly.',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ══════════════════════════════════════════════════════════════════════════

  void _addAiMsg(String text) {
    _messages.add(ChatMessage(text: text, isUser: false));
    _thinking = false;
    notifyListeners();
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> resetSession(PatientModel? patient) async {
    _messages.clear();
    _sessionReady = false;
    _todayQuestion = null;
    _prescribingDoctors = [];
    _loadedMeds = [];
    _pendingSymptoms = [];
    _gemini = GeminiService(role: GeminiRole.patient);
    notifyListeners();
    if (patient != null) await initSession(patient);
  }

  void clearChat() {
    _messages.clear();
    _sessionReady = false;
    _gemini = GeminiService(role: GeminiRole.patient);
    _pendingSymptoms = [];
    notifyListeners();
  }
}

void debugPrint(String msg) => print(msg);