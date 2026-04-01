import 'package:flutter/material.dart';
import '../models/queue_model.dart';
import '../services/firestore_service.dart';

class QueueProvider extends ChangeNotifier {
  final _db = FirestoreService();
  static const _clinicId = 'clinic_main'; // configurable

  List<QueueEntry> _entries = [];
  QueueEntry? _myEntry;
  bool _loading = false;

  List<QueueEntry> get entries => _entries;
  QueueEntry? get myEntry => _myEntry;
  bool get loading => _loading;

  int get myPosition {
    if (_myEntry == null) return -1;
    return _entries.indexWhere((e) => e.id == _myEntry!.id) + 1;
  }

  void startListening() {
    _db.queueStream(_clinicId).listen((entries) {
      _entries = entries;
      notifyListeners();
    });
  }

  Future<void> joinQueue({
    required String patientId,
    required String patientName,
    required List<String> symptoms,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      _myEntry = await _db.joinQueue(
        clinicId: _clinicId,
        patientId: patientId,
        patientName: patientName,
        symptoms: symptoms,
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> escalatePriority() async {
    if (_myEntry == null) return;
    await _db.updateQueuePriority(_clinicId, _myEntry!.id, 9);
  }
}
