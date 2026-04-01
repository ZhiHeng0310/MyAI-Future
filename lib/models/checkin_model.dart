class CheckIn {
  final String id;
  final String patientId;
  final String userMessage;
  final String aiResponse;
  final String risk; // "low" | "medium" | "high"
  final List<String> actionsTriggered;
  final DateTime createdAt;

  const CheckIn({
    required this.id,
    required this.patientId,
    required this.userMessage,
    required this.aiResponse,
    required this.risk,
    required this.actionsTriggered,
    required this.createdAt,
  });

  factory CheckIn.fromMap(Map<String, dynamic> m, String id) => CheckIn(
        id: id,
        patientId: m['patientId'] ?? '',
        userMessage: m['userMessage'] ?? '',
        aiResponse: m['aiResponse'] ?? '',
        risk: m['risk'] ?? 'low',
        actionsTriggered: List<String>.from(m['actionsTriggered'] ?? []),
        createdAt: m['createdAt'] != null
            ? (m['createdAt'] as dynamic).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'patientId': patientId,
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'risk': risk,
        'actionsTriggered': actionsTriggered,
        'createdAt': createdAt,
      };
}
