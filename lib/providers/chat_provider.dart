import 'dart:convert';
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
  final bool showCalendarPicker;
  final List<String> appointmentSymptoms;
  final DocumentAnalysis? documentAnalysis; // SPEC Feature 4
  final MedStatusResult? medicationStatus; // SPEC Feature 1

  ChatMessage({
    required this.text,
    required this.isUser,
    this.risk,
    this.actions = const [],
    DateTime? timestamp,
    this.hasImage = false,
    this.showCalendarPicker = false,
    this.appointmentSymptoms = const [],
    this.documentAnalysis,
    this.medicationStatus,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// SPEC Feature 1: Medication Check Result
class MedStatusResult {
  final List<Medication> all;
  final List<Medication> taken;
  final List<Medication> missed;
  final List<Medication> upcoming;
  final Medication? nextMedication;

  const MedStatusResult({
    required this.all,
    required this.taken,
    required this.missed,
    required this.upcoming,
    this.nextMedication,
  });

  bool get allTaken => missed.isEmpty && all.isNotEmpty;
  bool get noMeds => all.isEmpty;
  double get adherenceRate => all.isEmpty ? 1.0 : taken.length / all.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT PROVIDER - SPECIFICATION-COMPLIANT
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
  List<DoctorModel> _prescribingDoctors = []; // SPEC: Multiple doctors
  List<Medication> _loadedMeds = [];
  List<String> _pendingSymptoms = [];

  // Getters
  List<ChatMessage> get messages => _messages;
  bool get thinking => _thinking;
  bool get sessionReady => _sessionReady;
  String? get todayQuestion => _todayQuestion;
  PatientModel? get patient => _patient;

  void setQueueProvider(QueueProvider qp) => _queueProvider = qp;
  void setAppointmentProvider(AppointmentProvider ap) => _appointmentProvider = ap;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION INITIALIZATION - SPEC COMPLIANT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> initSession(PatientModel patient) async {
    if (_sessionReady) return;
    _patient = patient;

    // 1. Load medications
    try {
      _loadedMeds = await _db.getMedicationsForPatient(patient.id);
    } catch (_) {
      _loadedMeds = [];
    }

    // 2. SPEC: Get ALL prescribing doctors (no fixed assignment)
    _prescribingDoctors = await _getPrescribingDoctors(_loadedMeds);

    // 3. Build medication context
    final medNames = _loadedMeds
        .map((m) => '${m.name} ${m.dosage} (${m.frequency})')
        .toList();

    // 4. SPEC: List of prescribing doctor names
    final doctorNames = _prescribingDoctors.map((d) => d.name).toList();

    // 5. Init Gemini with prescription-based context
    try {
      await _gemini.initSession(
        name: patient.name,
        diagnosis: patient.diagnosis ?? 'General',
        daysSinceVisit: patient.daysSinceVisit,
        medications: medNames,
        prescribingDoctors: doctorNames, // SPEC: Multiple doctors
      );
    } catch (e) {
      debugPrint('⚠️ Gemini init: $e');
    }

    // 6. Generate check-in question
    _todayQuestion = await _gemini.generateCheckInQuestion(
        patient.diagnosis ?? 'General', patient.daysSinceVisit);

    _sessionReady = true;

    // 7. Welcome message
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

  /// SPEC: Get all doctors who prescribed medications to this patient
  Future<List<DoctorModel>> _getPrescribingDoctors(List<Medication> meds) async {
    // FIX: use doctorId (the correct field name on Medication model)
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
    _messages.add(ChatMessage(text: text, isUser: true));
    _thinking = true;
    notifyListeners();
    final response = await _gemini.sendMessage(text);
    await _processResponse(response, text, isImageScan: false);
  }

  Future<void> sendMessageWithImage(
      String text, Uint8List imageBytes, String mimeType) async {
    // SPEC Feature 4: Bill scanning
    final display = text.isEmpty
        ? '📄 Please scan this medication bill and show me the summary.'
        : text;
    _messages.add(ChatMessage(text: display, isUser: true, hasImage: true));

    _messages.add(ChatMessage(
      text: '📄 Scanning your document... I\'ll provide a clear summary with medication names, prices, and total cost.',
      isUser: false,
    ));
    _thinking = true;
    notifyListeners();

    final response = await _gemini.sendMessageWithImage(
        text, imageBytes, mimeType);

    // Remove pending message
    if (_messages.isNotEmpty && !_messages.last.isUser &&
        _messages.last.text.contains('Scanning')) {
      _messages.removeLast();
    }

    await _processResponse(response, text, isImageScan: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 2: APPOINTMENT BOOKING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> onDateSelected(DateTime date) async {
    if (_patient == null) return;

    _messages.add(ChatMessage(
      text: '📅 I\'d like to book on ${_fmtDate(date)}',
      isUser: true,
    ));
    _thinking = true;
    notifyListeners();

    try {
      // SPEC: Patient selects doctor (for now, use first prescribing doctor or any available)
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

      final booked = await _db.getBookedSlots(doctor.id, date);
      final schedule = DoctorSchedule(doctorId: doctor.id);
      final available = schedule.allSlots.where((s) => !booked.contains(s)).toList();

      if (available.isEmpty) {
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

      // Auto-book earliest slot
      final slot = available.first;
      final appt = await _db.bookAppointment(
        doctorId: doctor.id,
        doctorName: doctor.name,
        patientId: _patient!.id,
        patientName: _patient!.name,
        date: date,
        timeSlot: slot,
        symptoms: _pendingSymptoms.isNotEmpty
            ? _pendingSymptoms
            : ['General consultation'],
      );

      if (appt == null) {
        // Retry with next slot
        if (available.length > 1) {
          final appt2 = await _db.bookAppointment(
            doctorId: doctor.id,
            doctorName: doctor.name,
            patientId: _patient!.id,
            patientName: _patient!.name,
            date: date,
            timeSlot: available[1],
            symptoms: _pendingSymptoms.isNotEmpty ? _pendingSymptoms : ['General consultation'],
          );
          if (appt2 != null) {
            await _sendAppointmentNotifications(doctor, appt2);
            _addBookingSuccessMsg(appt2, doctor);
            _pendingSymptoms = [];
            return;
          }
        }
        _messages.add(ChatMessage(
          text: '😕 All slots were just taken. Please pick another date.',
          isUser: false,
          showCalendarPicker: true,
          appointmentSymptoms: _pendingSymptoms,
        ));
        _thinking = false;
        notifyListeners();
        return;
      }

      _appointmentProvider?.startListening(_patient!.id);
      await _sendAppointmentNotifications(doctor, appt);
      _addBookingSuccessMsg(appt, doctor);
      _pendingSymptoms = [];
    } catch (e) {
      debugPrint('❌ Booking error: $e');
      _addAiMsg('❌ Something went wrong. Please try again.');
    }
  }

  void _addBookingSuccessMsg(AppointmentSlot appt, DoctorModel doctor) {
    final symptomsText = (appt.symptoms.isNotEmpty)
        ? appt.symptoms.join(", ")
        : "General consultation";

    _messages.add(ChatMessage(
      text: '🎉 Appointment Booked Successfully!\n\n'
          '👨‍⚕️ Doctor: Dr. ${doctor.name}'
          '${doctor.specialization != null ? " (${doctor.specialization})" : ""}\n'
          '📅 Date: ${appt.dateLabel}\n'
          '🕐 Time: ${appt.timeSlot}\n'
          '📋 Reason: $symptomsText\n\n'
          'A confirmation has been sent to you. Please arrive 10 minutes early. 😊',
      isUser: false,
      actions: ['appointment_confirmed'],
    ));
    _thinking = false;
    notifyListeners();
  }

  /// SPEC: Send notifications to BOTH patient AND selected doctor
  Future<void> _sendAppointmentNotifications(
      DoctorModel doctor, AppointmentSlot appt) async {
    final symptomsText = appt.symptoms.isNotEmpty
        ? appt.symptoms.join(", ")
        : "General consultation";

    // 1. Notify PATIENT
    await NotificationService.showQueueStatusNotification(
      title: '✅ Appointment Confirmed!',
      body: 'Dr. ${doctor.name} on ${appt.dateLabel} at ${appt.timeSlot}',
    );
    await InboxService.sendAppointmentNotification(
      userId: _patient!.id,
      doctorName: doctor.name,
      appointmentTime: appt.date,
      appointmentId: appt.id,
    );
    await NotificationService.sendPushToUser(
      userId: _patient!.id,
      userCollection: 'patients',
      title: '✅ Appointment Confirmed!',
      body: 'Dr. ${doctor.name} — ${appt.dateLabel} at ${appt.timeSlot}',
      channel: 'careloop_queue',
    );

    // 2. SPEC: Notify SELECTED DOCTOR
    await _db.createDoctorInboxMessage(DoctorInboxMessage(
      id: '',
      doctorId: doctor.id,
      patientId: _patient!.id,
      patientName: _patient!.name,
      message: '📅 New appointment: ${_patient!.name} booked '
          '${appt.dateLabel} at ${appt.timeSlot}. '
          'Reason: $symptomsText',
      type: 'appointment_booked',
      read: false,
      createdAt: DateTime.now(),
    ));
    await NotificationService.sendPushToUser(
      userId: doctor.id,
      userCollection: 'doctors',
      title: '📅 New Appointment — ${_patient!.name}',
      body: '${appt.dateLabel} at ${appt.timeSlot}',
      channel: 'careloop_queue',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROCESS GEMINI RESPONSE - ALL 4 SPEC FEATURES
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

    // ────────────────────────────────────────────────────────────────────────
    // SPEC FEATURE 4: SCAN BILLS
    // ────────────────────────────────────────────────────────────────────────
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

    // ────────────────────────────────────────────────────────────────────────
    // SPEC FEATURE 1: MEDICATION CHECK
    // ────────────────────────────────────────────────────────────────────────
    if (response.checkMedications) {
      finalActs.remove('check_medications');
      showCal = false;

      medStatus = await _checkMedicationStatus();
      msg = _buildMedicationStatusMessage(medStatus);

      // Send reminders for missed medications
      if (medStatus != null && !medStatus.noMeds && !medStatus.allTaken) {
        for (final med in medStatus.missed) {
          await NotificationService.showMedicationReminder(med.name, med.dosage);
          if (_patient != null) {
            await InboxService.sendMedicationReminder(
              userId: _patient!.id,
              medicationName: med.name,
              dosage: med.dosage,
              medicationId: med.id,
            );
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

    // ────────────────────────────────────────────────────────────────────────
    // SPEC FEATURE 3: I FEEL UNWELL - Alert ALL prescribing doctors
    // ────────────────────────────────────────────────────────────────────────
    if (response.feelUnwell || response.actions.contains('alert_all_doctors')) {
      await _handleFeelUnwell(userText, response.unwellSymptoms, response.risk.name);

      if (!msg.contains('doctor') && !msg.contains('alert')) {
        msg = '$msg\n\n'
            '🔔 I\'ve notified ALL your prescribing doctors about your symptoms. '
            'They will review and send advice back to you shortly.';
      }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SPEC FEATURE 2: BOOK APPOINTMENT
    // ────────────────────────────────────────────────────────────────────────
    if (response.appointmentIntent || response.actions.contains('book_appointment')) {
      showCal = true;
      _pendingSymptoms = response.appointmentSymptoms;
      finalActs.remove('book_appointment');

      if (!msg.contains('calendar') && !msg.contains('date')) {
        msg = '$msg\n\nPlease pick a date from the calendar below — '
            'I\'ll book the earliest available slot for you! 📅';
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
  // SPEC FEATURE 1: MEDICATION CHECK IMPLEMENTATION
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

      for (final med in meds) {
        if (!med.active) continue;

        // SPEC: Compare current time with medication schedule
        final times = _parseMedicationTimes(med.frequency);

        for (final time in times) {
          final scheduledTime = DateTime(
            now.year, now.month, now.day,
            time.hour, time.minute,
          );

          if (now.isAfter(scheduledTime)) {
            // Time has passed
            if (med.isTakenToday) {
              if (!taken.contains(med)) taken.add(med);
            } else {
              // SPEC: Medication time passed and not taken → missed
              if (!missed.contains(med)) missed.add(med);
            }
          } else {
            // Upcoming medication
            if (!upcoming.contains(med)) upcoming.add(med);
            if (nextMed == null || scheduledTime.isBefore(
                DateTime(now.year, now.month, now.day,
                    _parseMedicationTimes(nextMed.frequency).first.hour,
                    _parseMedicationTimes(nextMed.frequency).first.minute))) {
              nextMed = med;
            }
          }
        }
      }

      return MedStatusResult(
        all: meds,
        taken: taken,
        missed: missed,
        upcoming: upcoming,
        nextMedication: nextMed,
      );
    } catch (e) {
      debugPrint('❌ Med status check: $e');
      return null;
    }
  }

  List<TimeOfDay> _parseMedicationTimes(String frequency) {
    final times = <TimeOfDay>[];

    if (frequency.contains('1x') || frequency.contains('once') ||
        frequency.toLowerCase().contains('once daily')) {
      times.add(const TimeOfDay(hour: 9, minute: 0));
    } else if (frequency.contains('2x') || frequency.contains('twice') ||
        frequency.toLowerCase().contains('twice daily')) {
      times.add(const TimeOfDay(hour: 9, minute: 0));
      times.add(const TimeOfDay(hour: 21, minute: 0));
    } else if (frequency.contains('3x') ||
        frequency.toLowerCase().contains('three times')) {
      times.add(const TimeOfDay(hour: 9, minute: 0));
      times.add(const TimeOfDay(hour: 14, minute: 0));
      times.add(const TimeOfDay(hour: 21, minute: 0));
    } else {
      times.add(const TimeOfDay(hour: 9, minute: 0));
    }

    return times;
  }

  String _buildMedicationStatusMessage(MedStatusResult? s) {
    if (s == null) {
      return '❌ Could not retrieve your medication data. Please try again.';
    }

    if (s.noMeds) {
      return 'You don\'t have any medications prescribed yet. '
          'Your doctor will prescribe medications after your consultation.';
    }

    if (s.allTaken) {
      return '✅ You\'re all up to date! You\'ve taken all your medications today.\n\n'
          '${s.all.map((m) => '✓ ${m.name} (${m.dosage})').join('\n')}\n\n'
          'Great job keeping up with your medication schedule! 💊';
    }

    if (s.missed.isNotEmpty) {
      final missedList = s.missed.map((m) =>
      '⚠️ ${m.name} (${m.dosage}) - ${m.frequency}').join('\n');
      return '⚠️ You missed ${s.missed.length} medication(s). Please take them now:\n\n'
          '$missedList\n\n'
          'I\'ve sent you a reminder notification. Please take them as soon as possible! 💊';
    }

    if (s.nextMedication != null) {
      final next = s.nextMedication!;
      final nextTime = _parseMedicationTimes(next.frequency).first;
      return '📋 Next medication:\n\n'
          '💊 ${next.name} (${next.dosage})\n'
          '🕐 Time: ${nextTime.hour}:${nextTime.minute.toString().padLeft(2, '0')}\n'
          '📝 Frequency: ${next.frequency}\n\n'
          'I\'ll remind you when it\'s time to take it!';
    }

    return 'All medications are on schedule! ✅';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEC FEATURE 3: I FEEL UNWELL - Alert ALL prescribing doctors
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleFeelUnwell(
      String message, List<String> symptoms, String riskLevel) async {
    if (_patient == null) return;

    // SPEC: Send alert to ALL doctors who prescribed medication to this patient
    if (_prescribingDoctors.isEmpty) {
      try {
        final all = await _db.getAllDoctors();
        if (all.isNotEmpty) {
          _prescribingDoctors = [all.first];
        }
      } catch (_) {}
    }

    if (_prescribingDoctors.isEmpty) {
      await NotificationService.showHealthAlert(
          '${_patient!.name} reported: $message');
      return;
    }

    // SPEC: Alert ALL prescribing doctors
    for (final doctor in _prescribingDoctors) {
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
        read: false,
        createdAt: DateTime.now(),
      ));

      debugPrint('✅ Sent health alert to Dr. ${doctor.name}');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ══════════════════════════════════════════════════════════════════════════

  void _addAiMsg(String text) {
    _messages.add(ChatMessage(text: text, isUser: false));
    _thinking = false;
    notifyListeners();
  }

  String _fmtDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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