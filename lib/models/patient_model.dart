class PatientModel {
  final String       id;
  final String       name;
  final String       email;
  final String?      phone;
  final String?      diagnosis;
  final DateTime?    lastVisit;
  final List<String> allergies;

  /// Legacy field kept for backwards compatibility.
  /// Active doctor relationships are derived from medication prescriptions.
  final String? assignedDoctorId;

  const PatientModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.diagnosis,
    this.lastVisit,
    this.allergies          = const [],
    this.assignedDoctorId,
  });

  int get daysSinceVisit {
    if (lastVisit == null) return 0;
    return DateTime.now().difference(lastVisit!).inDays;
  }

  bool get hasAssignedDoctor => assignedDoctorId != null && assignedDoctorId!.isNotEmpty;

  factory PatientModel.fromMap(Map<String, dynamic> m, String id) =>
      PatientModel(
        id:               id,
        name:             m['name']             ?? '',
        email:            m['email']            ?? '',
        phone:            m['phone'],
        diagnosis:        m['diagnosis'],
        lastVisit: m['lastVisit'] != null
            ? (m['lastVisit'] as dynamic).toDate()
            : null,
        allergies:        List<String>.from(m['allergies'] ?? []),
        assignedDoctorId: m['assignedDoctorId'],
      );

  Map<String, dynamic> toMap() => {
    'name':             name,
    'email':            email,
    'phone':            phone,
    'diagnosis':        diagnosis,
    'lastVisit':        lastVisit,
    'allergies':        allergies,
    'assignedDoctorId': assignedDoctorId,
  };

  PatientModel copyWith({String? assignedDoctorId}) => PatientModel(
    id:               id,
    name:             name,
    email:            email,
    phone:            phone,
    diagnosis:        diagnosis,
    lastVisit:        lastVisit,
    allergies:        allergies,
    assignedDoctorId: assignedDoctorId ?? this.assignedDoctorId,
  );
}
