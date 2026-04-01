import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class MedicationProvider extends ChangeNotifier {
  final _db = FirestoreService();
  List<Medication> _medications = [];

  List<Medication> get medications  => _medications;
  int    get takenToday     => _medications.where((m) => m.isTakenToday).length;
  double get adherenceRate  =>
      _medications.isEmpty ? 0 : takenToday / _medications.length;

  void startListening(String patientId) {
    _db.medicationsStream(patientId).listen((meds) {
      _medications = meds;
      _scheduleNotifications(meds);
      notifyListeners();
    });
  }

  /// Schedule a daily local notification for every reminder time on every
  /// active medication.  This runs every time Firestore emits a new snapshot,
  /// so new medications added by the doctor are picked up automatically.
  void _scheduleNotifications(List<Medication> meds) {
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

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.logDose(medicationId, taken);
    final idx = _medications.indexWhere((m) => m.id == medicationId);
    if (idx != -1) notifyListeners();
  }
}