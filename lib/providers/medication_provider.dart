import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class MedicationProvider extends ChangeNotifier {
  final _db = FirestoreService();

  List<Medication> _medications  = [];
  Timer?           _agentTimer;

  /// Set of "YYYY-MM-DD_medId_timeSlot" keys — prevents double-firing
  /// the same missed-dose notification within a day.
  final Set<String> _notifiedSlots = {};

  List<Medication> get medications => _medications;

  /// Total slots taken today across all medications.
  int get takenSlotsToday =>
      _medications.fold(0, (s, m) => s + m.takenSlotsToday);

  /// Total slots expected today across all medications.
  int get totalSlotsToday =>
      _medications.fold(0, (s, m) => s + m.totalSlotsToday);

  /// Adherence 0.0–1.0 based on slot-level tracking.
  double get adherenceRate =>
      totalSlotsToday == 0 ? 0 : takenSlotsToday / totalSlotsToday;

  /// Legacy — how many medications are fully taken today.
  int get takenToday => _medications.where((m) => m.isTakenToday).length;

  // ── Start listening ───────────────────────────────────────────────────────
  void startListening(String patientId) {
    _db.medicationsStream(patientId).listen((meds) {
      _medications = meds;
      _scheduleSystemNotifications(meds);
      notifyListeners();
    });

    // Agentic missed-dose checker — every 60 seconds
    _agentTimer?.cancel();
    _agentTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkMissedDoses());
    Future.delayed(const Duration(seconds: 10), _checkMissedDoses);
  }

  // ── Agentic checker ───────────────────────────────────────────────────────
  /// Fires a notification for each missed slot that is exactly 5 minutes overdue.
  /// De-duplicates using _notifiedSlots so it only fires once per slot per day.
  void _checkMissedDoses() {
    final now        = DateTime.now();
    final todayStr   = Medication.slotKey('marker').split('_').first; // "YYYY-MM-DD"
    final nowMinutes = now.hour * 60 + now.minute;

    // Clear stale notifications from previous days
    _notifiedSlots.removeWhere((k) => !k.startsWith(todayStr));

    for (final med in _medications.where((m) => m.active)) {
      for (final timeStr in med.reminderTimes) {
        final slotMins = _parseTime(timeStr);
        if (slotMins == null) continue;

        final diff      = nowMinutes - slotMins; // minutes since reminder time
        final notifKey  = '${todayStr}_${med.id}_$timeStr';

        // Fire once, 5–7 minutes after the reminder, if slot not yet taken
        if (diff >= 5 && diff <= 7 &&
            !med.isTakenForSlot(timeStr) &&
            !_notifiedSlots.contains(notifKey)) {
          _notifiedSlots.add(notifKey);
          debugPrint('AgentTimer: missed dose "${med.name}" at $timeStr — notifying');
          NotificationService.showMedicationReminder(med.name, med.dosage);
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

  /// Legacy — for medications with no reminder times.
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