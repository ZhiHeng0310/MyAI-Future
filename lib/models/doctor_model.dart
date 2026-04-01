class DoctorModel {
  final String id;
  final String name;
  final String email;
  final String doctorId;       // e.g. "MMC-12345"
  final String? specialization;
  final String clinicId;

  const DoctorModel({
    required this.id,
    required this.name,
    required this.email,
    required this.doctorId,
    this.specialization,
    this.clinicId = 'clinic_main',
  });

  factory DoctorModel.fromMap(Map<String, dynamic> m, String id) => DoctorModel(
    id: id,
    name: m['name'] ?? '',
    email: m['email'] ?? '',
    doctorId: m['doctorId'] ?? '',
    specialization: m['specialization'],
    clinicId: m['clinicId'] ?? 'clinic_main',
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'doctorId': doctorId,
    'specialization': specialization,
    'clinicId': clinicId,
    'role': 'doctor',
  };
}