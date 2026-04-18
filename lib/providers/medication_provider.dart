import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../models/patient_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';

class MedicationProvider extends ChangeNotifier {
  final _db = FirestoreService();

  List<Medication> _medications  = [];
  Timer?           _agentTimer;
  PatientModel?    _patient;

  /// Set of "YYYY-MM-DD_medId_timeSlot" keys — prevents double-firing
  final Set<String> _notifiedSlots = {};

  List<Medication> get medications => _medications;

  int get takenSlotsToday =>
      _medications.fold(0, (s, m) => s + m.takenSlotsToday);

  int get totalSlotsToday =>
      _medications.fold(0, (s, m) => s + m.totalSlotsToday);

  double get adherenceRate =>
      totalSlotsToday == 0 ? 0 : takenSlotsToday / totalSlotsToday;

  int get takenToday => _medications.where((m) => m.isTakenToday).length;

  // ── Start listening ───────────────────────────────────────────────────────
  void startListening(String patientId, {PatientModel? patient}) {
    _patient = patient;
    _db.medicationsStream(patientId).listen((meds) {
      _medications = meds;
      _scheduleSystemNotifications(meds);
      notifyListeners();
    });

    // Agentic missed-dose checker — every 60 seconds
    _agentTimer?.cancel();
    _agentTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _checkMissedDoses());
    Future.delayed(const Duration(seconds: 10), _checkMissedDoses);
  }

  // ── Update patient reference ──────────────────────────────────────────────
  void setPatient(PatientModel patient) {
    _patient = patient;
  }

  // ✅ FIX 3: Enhanced agentic checker with COMPREHENSIVE notifications
  void _checkMissedDoses() {
    final now        = DateTime.now();
    final todayStr   = Medication.slotKey('marker').split('_').first;
    final nowMinutes = now.hour * 60 + now.minute;

    _notifiedSlots.removeWhere((k) => !k.startsWith(todayStr));

    for (final med in _medications.where((m) => m.active)) {
      for (final timeStr in med.reminderTimes) {
        final slotMins = _parseTime(timeStr);
        if (slotMins == null) continue;

        final diff      = nowMinutes - slotMins;
        final notifKey  = '${todayStr}_${med.id}_$timeStr';

        // Fire once, 5–7 minutes after the reminder, if slot not yet taken
        if (diff >= 5 && diff <= 7 &&
            !med.isTakenForSlot(timeStr) &&
            !_notifiedSlots.contains(notifKey)) {
          _notifiedSlots.add(notifKey);
          debugPrint('🔔 AgentTimer: missed dose "${med.name}" at $timeStr — notifying');

          // ✅ FIX 3: Send THREE types of notifications for missed medication

          // 1. Local OS notification (immediate, works even if app closed)
          NotificationService.showMedicationReminder(med.name, med.dosage);
          debugPrint('✅ Sent local notification for ${med.name}');

          // 2. Inbox notification (persistent in-app notification)
          if (_patient != null) {
            InboxService.sendMedicationReminder(
              userId:         _patient!.id,
              medicationName: med.name,
              dosage:         med.dosage,
              medicationId:   med.id,
            );
            debugPrint('✅ Sent inbox notification for ${med.name}');
          }

          // 3. Push notification (Firebase Cloud Messaging - works background/terminated)
          if (_patient != null) {
            NotificationService.sendPushToUser(
              userId:         _patient!.id,
              userCollection: 'patient',
              title:          '💊 Missed Medication',
              body:           'Time to take ${med.name} (${med.dosage}). You\'re 5 minutes late!',
              channel:        'careloop_meds',
            );
            debugPrint('✅ Sent push notification for ${med.name}');
          }
        }
      }
    }
  }

  int? _parseTime(String t) {
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  // ── Schedule OS-level daily reminders ────────────────────────────────────
  void _scheduleSystemNotifications(List<Medication> meds) {
    for (final med in meds.where((m) => m.active)) {
      for (int i = 0; i < med.reminderTimes.length; i++) {
        NotificationService.scheduleMedicationReminder(
          id:             NotificationService.medNotificationId(med.id, i),
          medicationName: med.name,
          dosage:         med.dosage,
          time:           med.reminderTimes[i],
        );
      }
    }
  }

  // ── Log a specific time-slot dose ────────────────────────────────────────
  Future<void> logDoseForSlot(
      String medicationId, String timeSlot, bool taken) async {
    await _db.logDoseForSlot(medicationId, timeSlot, taken);
    notifyListeners();
  }

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.logDose(medicationId, taken);
    notifyListeners();
  }

  @override
  void dispose() {
    _agentTimer?.cancel();
    super.dispose();
  }
}