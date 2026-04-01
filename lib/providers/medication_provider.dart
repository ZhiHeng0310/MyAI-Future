import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/firestore_service.dart';

class MedicationProvider extends ChangeNotifier {
  final _db = FirestoreService();
  List<Medication> _medications = [];

  List<Medication> get medications => _medications;
  int get takenToday => _medications.where((m) => m.isTakenToday).length;
  double get adherenceRate =>
      _medications.isEmpty ? 0 : takenToday / _medications.length;

  void startListening(String patientId) {
    _db.medicationsStream(patientId).listen((meds) {
      _medications = meds;
      notifyListeners();
    });
  }

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.logDose(medicationId, taken);
    // Optimistic update
    final idx = _medications.indexWhere((m) => m.id == medicationId);
    if (idx != -1) notifyListeners();
  }
}
