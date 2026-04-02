class Medication {
  final String       id;
  final String       patientId;
  final String       name;
  final String       dosage;
  final String       frequency;
  final List<String> reminderTimes;
  final bool         active;
  final DateTime?    lastTaken;

  /// Each entry is "YYYY-MM-DD_HH:mm", e.g. "2025-01-15_08:00".
  /// Automatically resets each day because the date prefix changes.
  final List<String> takenSlots;

  const Medication({
    required this.id,
    required this.patientId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.reminderTimes,
    this.active     = true,
    this.lastTaken,
    this.takenSlots = const [],
  });

  // ── Per-slot helpers ──────────────────────────────────────────────────────

  /// Whether [timeSlot] (e.g. "08:00") has been marked taken today.
  bool isTakenForSlot(String timeSlot) =>
      takenSlots.contains('${_todayPrefix()}_$timeSlot');

  /// Number of slots taken today (across all reminder times).
  int get takenSlotsToday {
    if (reminderTimes.isEmpty) return isTakenToday ? 1 : 0;
    return reminderTimes.where(isTakenForSlot).length;
  }

  /// Total slots expected today.
  int get totalSlotsToday =>
      reminderTimes.isEmpty ? 1 : reminderTimes.length;

  // ── Legacy / summary helpers ──────────────────────────────────────────────

  /// True when ALL reminder slots are taken today (or lastTaken = today for
  /// medications without reminder times).
  bool get isTakenToday {
    if (reminderTimes.isEmpty) {
      if (lastTaken == null) return false;
      final now = DateTime.now();
      return lastTaken!.year  == now.year  &&
          lastTaken!.month == now.month &&
          lastTaken!.day   == now.day;
    }
    return reminderTimes.every(isTakenForSlot);
  }

  /// True when at least one slot is taken today.
  bool get isAnyTakenToday {
    if (reminderTimes.isEmpty) return isTakenToday;
    return reminderTimes.any(isTakenForSlot);
  }

  // ── Date key ──────────────────────────────────────────────────────────────
  static String _todayPrefix() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String slotKey(String timeSlot) => '${_todayPrefix()}_$timeSlot';

  // ── Firestore ─────────────────────────────────────────────────────────────
  factory Medication.fromMap(Map<String, dynamic> m, String id) => Medication(
    id:            id,
    patientId:     m['patientId']   ?? '',
    name:          m['name']        ?? '',
    dosage:        m['dosage']      ?? '',
    frequency:     m['frequency']   ?? '',
    reminderTimes: List<String>.from(m['reminderTimes'] ?? []),
    active:        m['active']      ?? true,
    lastTaken: m['lastTaken'] != null
        ? (m['lastTaken'] as dynamic).toDate()
        : null,
    takenSlots: List<String>.from(m['takenSlots'] ?? []),
  );

  Map<String, dynamic> toMap() => {
    'patientId':    patientId,
    'name':         name,
    'dosage':       dosage,
    'frequency':    frequency,
    'reminderTimes': reminderTimes,
    'active':       active,
    'lastTaken':    lastTaken,
    'takenSlots':   takenSlots,
  };
}

// ─── CheckIn model (unchanged) ───────────────────────────────────────────────
enum RiskLevel { low, medium, high }

class MedicationCheckIn {
  final String       id;
  final String       patientId;
  final String       userMessage;
  final String       aiResponse;
  final RiskLevel    risk;
  final List<String> actionsTriggered;
  final DateTime     createdAt;

  const MedicationCheckIn({
    required this.id,
    required this.patientId,
    required this.userMessage,
    required this.aiResponse,
    required this.risk,
    required this.actionsTriggered,
    required this.createdAt,
  });

  factory MedicationCheckIn.fromMap(Map<String, dynamic> m, String id) =>
      MedicationCheckIn(
        id:               id,
        patientId:        m['patientId']    ?? '',
        userMessage:      m['userMessage']  ?? '',
        aiResponse:       m['aiResponse']   ?? '',
        risk: RiskLevel.values.firstWhere(
                (e) => e.name == m['risk'], orElse: () => RiskLevel.low),
        actionsTriggered: List<String>.from(m['actionsTriggered'] ?? []),
        createdAt: m['createdAt'] != null
            ? (m['createdAt'] as dynamic).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
    'patientId':        patientId,
    'userMessage':      userMessage,
    'aiResponse':       aiResponse,
    'risk':             risk.name,
    'actionsTriggered': actionsTriggered,
    'createdAt':        createdAt,
  };
}