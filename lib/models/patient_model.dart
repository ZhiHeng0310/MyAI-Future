// ─── Patient Model ────────────────────────────────────────────────────────────

class PatientModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? diagnosis;
  final DateTime? lastVisit;
  final List<String> allergies;

  const PatientModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.diagnosis,
    this.lastVisit,
    this.allergies = const [],
  });

  int get daysSinceVisit {
    if (lastVisit == null) return 0;
    return DateTime.now().difference(lastVisit!).inDays;
  }

  factory PatientModel.fromMap(Map<String, dynamic> m, String id) => PatientModel(
        id: id,
        name: m['name'] ?? '',
        email: m['email'] ?? '',
        phone: m['phone'],
        diagnosis: m['diagnosis'],
        lastVisit: m['lastVisit'] != null
            ? (m['lastVisit'] as dynamic).toDate()
            : null,
        allergies: List<String>.from(m['allergies'] ?? []),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'diagnosis': diagnosis,
        'lastVisit': lastVisit,
        'allergies': allergies,
      };
}
