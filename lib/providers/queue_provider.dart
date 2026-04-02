import 'package:flutter/material.dart';
import '../models/queue_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class QueueProvider extends ChangeNotifier {
  final _db             = FirestoreService();
  static const _clinicId = 'clinic_main';

  List<QueueEntry> _entries            = [];
  QueueEntry?      _myEntry;
  bool             _loading            = false;
  int              _prevPriority       = 0;  // detect urgent escalation

  List<QueueEntry> get entries  => _entries;
  QueueEntry?      get myEntry  => _myEntry;
  bool             get loading  => _loading;

  int get myPosition {
    if (_myEntry == null) return -1;
    final idx = _entries.indexWhere((e) => e.id == _myEntry!.id);
    return idx == -1 ? -1 : idx + 1;
  }

  /// Plain int — safe for string interpolation. No function reference.
  int get myEstimatedWait => QueueEntry.waitMinutesForPosition(myPosition);

  bool get isAlreadyInQueue =>
      _myEntry != null && _myEntry!.status != QueueStatus.done;

  // ── Start listening — restores existing entry across login/logout ─────────
  Future<void> startListening(String patientId) async {
    final existing = await _db.findActiveQueueEntry(_clinicId, patientId);
    if (existing != null) {
      _myEntry       = existing;
      _prevPriority  = existing.priority;
      notifyListeners();
    }

    _db.queueStream(_clinicId).listen((entries) {
      _entries = entries;

      if (_myEntry != null) {
        final fresh = entries.where((e) => e.id == _myEntry!.id);
        if (fresh.isNotEmpty) {
          final updated = fresh.first;

          // ── Detect status change → notify patient ───────────────────────
          if (updated.status != _myEntry!.status) {
            _onStatusChanged(updated.status, myPosition);
          }

          // ── Detect priority escalation (doctor pressed Urgent) ──────────
          if (updated.priority > _prevPriority && updated.priority >= 9) {
            NotificationService.showQueueStatusNotification(
              title: '⚡ Your queue priority has been raised',
              body:  'You have been moved up in the queue due to urgent symptoms.',
            );
          }
          _prevPriority = updated.priority;
          _myEntry      = updated;
        } else {
          // Entry deleted by doctor (Remove)
          _myEntry = null;
        }
      }
      notifyListeners();
    });
  }

  void _onStatusChanged(QueueStatus newStatus, int pos) {
    switch (newStatus) {
      case QueueStatus.called:
        NotificationService.showQueueStatusNotification(
          title: '🏥 It\'s your turn!',
          body:  'The doctor is ready for you. Please proceed to the consultation room now.',
        );
        break;
      case QueueStatus.inProgress:
        NotificationService.showQueueStatusNotification(
          title: '🏥 Consultation in progress',
          body:  'Your consultation has started.',
        );
        break;
      case QueueStatus.done:
        NotificationService.showQueueStatusNotification(
          title: '✅ Consultation complete',
          body:  'Your visit is complete. We hope you feel better soon!',
        );
        break;
      default:
        break;
    }
  }

  Future<void> joinQueue({
    required String       patientId,
    required String       patientName,
    required List<String> symptoms,
  }) async {
    if (isAlreadyInQueue) return;
    _loading = true;
    notifyListeners();
    try {
      _myEntry      = await _db.joinQueue(
        clinicId:    _clinicId,
        patientId:   patientId,
        patientName: patientName,
        symptoms:    symptoms,
      );
      _prevPriority = _myEntry!.priority;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> escalatePriority() async {
    if (_myEntry == null) return;
    await _db.updateQueuePriority(_clinicId, _myEntry!.id, 9);
  }

  void clear() {
    _entries      = [];
    _myEntry      = null;
    _prevPriority = 0;
    notifyListeners();
  }
}