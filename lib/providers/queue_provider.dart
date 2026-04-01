import 'package:flutter/material.dart';
import '../models/queue_model.dart';
import '../services/firestore_service.dart';

class QueueProvider extends ChangeNotifier {
  final _db = FirestoreService();
  static const _clinicId = 'clinic_main';

  List<QueueEntry> _entries  = [];
  QueueEntry?      _myEntry;
  bool             _loading  = false;

  List<QueueEntry> get entries => _entries;
  QueueEntry?      get myEntry => _myEntry;
  bool             get loading => _loading;

  /// 1-based position of this patient in the queue, or -1 if not in queue.
  int get myPosition {
    if (_myEntry == null) return -1;
    final idx = _entries.indexWhere((e) => e.id == _myEntry!.id);
    return idx == -1 ? -1 : idx + 1;
  }

  /// Dynamic wait time based on actual queue position.
  int get myEstimatedWait {
    final pos = myPosition;
    if (pos <= 0) return 0;
    // Each patient ahead takes ~10 minutes
    return (pos - 1) * 10;
  }

  /// Whether this patient already has an active (non-done) queue entry.
  bool get isAlreadyInQueue =>
      _myEntry != null &&
          _myEntry!.status != QueueStatus.done;

  /// Call on login — both starts the live stream AND recovers any existing
  /// queue entry the patient already had (survives logout/login).
  Future<void> startListening(String patientId) async {
    // 1. Restore existing entry from Firestore (survives app restarts)
    final existing =
    await _db.findActiveQueueEntry(_clinicId, patientId);
    if (existing != null) {
      _myEntry = existing;
      notifyListeners();
    }

    // 2. Live stream — keeps queue list and myEntry in sync
    _db.queueStream(_clinicId).listen((entries) {
      _entries = entries;

      // Keep _myEntry reference fresh from the live list
      if (_myEntry != null) {
        final fresh = entries.where((e) => e.id == _myEntry!.id);
        if (fresh.isNotEmpty) {
          _myEntry = fresh.first;
        } else {
          // Entry was removed by doctor — clear it
          _myEntry = null;
        }
      }
      notifyListeners();
    });
  }

  Future<void> joinQueue({
    required String patientId,
    required String patientName,
    required List<String> symptoms,
  }) async {
    // Guard: one active entry per patient
    if (isAlreadyInQueue) return;

    _loading = true;
    notifyListeners();
    try {
      _myEntry = await _db.joinQueue(
        clinicId:    _clinicId,
        patientId:   patientId,
        patientName: patientName,
        symptoms:    symptoms,
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

  /// Called when auth signs out — clears in-memory state only.
  void clear() {
    _entries = [];
    _myEntry = null;
    notifyListeners();
  }
}