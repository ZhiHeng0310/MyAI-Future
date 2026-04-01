// ─── Medication Model ─────────────────────────────────────────────────────────

class Medication {
  final String id;
  final String patientId;
  final String name;
  final String dosage;
  final String frequency; // e.g. "twice daily"
  final List<String> reminderTimes; // e.g. ["08:00", "20:00"]
  final bool active;
  final DateTime? lastTaken;

  const Medication({
    required this.id,
    required this.patientId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.reminderTimes,
    this.active = true,
    this.lastTaken,
  });

  bool get isTakenToday {
    if (lastTaken == null) return false;
    final now = DateTime.now();
    return lastTaken!.year == now.year &&
        lastTaken!.month == now.month &&
        lastTaken!.day == now.day;
  }

  factory Medication.fromMap(Map<String, dynamic> m, String id) => Medication(
        id: id,
        patientId: m['patientId'] ?? '',
        name: m['name'] ?? '',
        dosage: m['dosage'] ?? '',
        frequency: m['frequency'] ?? '',
        reminderTimes: List<String>.from(m['reminderTimes'] ?? []),
        active: m['active'] ?? true,
        lastTaken: m['lastTaken'] != null
            ? (m['lastTaken'] as dynamic).toDate()
            : null,
      );

  Map<String, dynamic> toMap() => {
        'patientId': patientId,
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'reminderTimes': reminderTimes,
        'active': active,
        'lastTaken': lastTaken,
      };
}

// ─── CheckIn Model ────────────────────────────────────────────────────────────

enum RiskLevel { low, medium, high }

class MedicationCheckIn {
  final String id;
  final String patientId;
  final String userMessage;
  final String aiResponse;
  final RiskLevel risk;
  final List<String> actionsTriggered;
  final DateTime createdAt;

  const MedicationCheckIn({
    required this.id,
    required this.patientId,
    required this.userMessage,
    required this.aiResponse,
    required this.risk,
    required this.actionsTriggered,
    required this.createdAt,
  });

  factory MedicationCheckIn.fromMap(Map<String, dynamic> m, String id) => MedicationCheckIn(
        id: id,
        patientId: m['patientId'] ?? '',
        userMessage: m['userMessage'] ?? '',
        aiResponse: m['aiResponse'] ?? '',
        risk: RiskLevel.values.firstWhere(
          (e) => e.name == m['risk'],
          orElse: () => RiskLevel.low,
        ),
        actionsTriggered: List<String>.from(m['actionsTriggered'] ?? []),
        createdAt: m['createdAt'] != null
            ? (m['createdAt'] as dynamic).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'patientId': patientId,
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'risk': risk.name,
        'actionsTriggered': actionsTriggered,
        'createdAt': createdAt,
      };
}
