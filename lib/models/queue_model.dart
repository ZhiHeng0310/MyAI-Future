enum QueueStatus { waiting, called, inProgress, done }

class QueueEntry {
  final String      id;
  final String      patientId;
  final String      patientName;
  final List<String> symptoms;
  final int         priority;
  final QueueStatus status;
  final DateTime    joinedAt;

  const QueueEntry({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.symptoms,
    required this.priority,
    required this.status,
    required this.joinedAt,
  });

  /// Dynamic wait: each person ahead takes ~10 minutes.
  /// [position] is 1-based rank in the sorted queue.
  /// If position not supplied, falls back to priority-based rough estimate.
  int estimatedWaitMinutes({int position = 0}) {
    if (position > 0) {
      // 10 minutes per person ahead of this patient (position - 1 people ahead)
      return (position - 1) * 10;
    }
    // Fallback when position unknown
    if (priority >= 9) return 5;
    if (priority >= 7) return 15;
    return 30;
  }

  factory QueueEntry.fromMap(Map<String, dynamic> m, String id) => QueueEntry(
    id:          id,
    patientId:   m['patientId']   ?? '',
    patientName: m['patientName'] ?? '',
    symptoms:    List<String>.from(m['symptoms'] ?? []),
    priority:    (m['priority'] as num?)?.toInt() ?? 5,
    status:      QueueStatus.values.firstWhere(
          (e) => e.name == m['status'],
      orElse: () => QueueStatus.waiting,
    ),
    joinedAt: m['joinedAt'] != null
        ? (m['joinedAt'] as dynamic).toDate()
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'patientId':   patientId,
    'patientName': patientName,
    'symptoms':    symptoms,
    'priority':    priority,
    'status':      status.name,
    'joinedAt':    joinedAt,
  };
}