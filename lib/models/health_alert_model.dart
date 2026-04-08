import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HEALTH ALERT MODEL
// ═══════════════════════════════════════════════════════════════════════════

class HealthAlert {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String message;
  final String riskLevel; // "low" | "medium" | "high"
  final String status; // "pending" | "acknowledged" | "responded"
  final String? doctorResponse;
  final DateTime createdAt;

  const HealthAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.message,
    required this.riskLevel,
    required this.status,
    this.doctorResponse,
    required this.createdAt,
  });

  factory HealthAlert.fromMap(Map<String, dynamic> m, String id) => HealthAlert(
    id: id,
    patientId: m['patientId'] ?? '',
    patientName: m['patientName'] ?? '',
    doctorId: m['doctorId'] ?? '',
    message: m['message'] ?? '',
    riskLevel: m['riskLevel'] ?? 'low',
    status: m['status'] ?? 'pending',
    doctorResponse: m['doctorResponse'],
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'patientName': patientName,
    'doctorId': doctorId,
    'message': message,
    'riskLevel': riskLevel,
    'status': status,
    'doctorResponse': doctorResponse,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// DOCTOR INBOX MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════════════

class DoctorInboxMessage {
  final String id;
  final String doctorId;
  final String patientId;
  final String patientName;
  final String message;
  final String type; // 'appointment_booked', 'health_alert', etc.
  final bool read;
  final DateTime createdAt;

  DoctorInboxMessage({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
  });

  factory DoctorInboxMessage.fromMap(Map<String, dynamic> m, String id) => DoctorInboxMessage(
    id: id,
    doctorId: m['doctorId'] ?? '',
    patientId: m['patientId'] ?? '',
    patientName: m['patientName'] ?? '',
    message: m['message'] ?? '',
    type: m['type'] ?? '',
    read: m['read'] ?? false,
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'doctorId': doctorId,
    'patientId': patientId,
    'patientName': patientName,
    'message': message,
    'type': type,
    'read': read,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// PATIENT INBOX MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════════════

class PatientInboxMessage {
  final String id;
  final String patientId;
  final String doctorId;
  final String doctorName;
  final String message;
  final String type; // 'doctor_note', 'appointment_request', 'doctor_check', etc.
  final bool read;
  final DateTime createdAt;

  PatientInboxMessage({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
  });

  factory PatientInboxMessage.fromMap(Map<String, dynamic> m, String id) => PatientInboxMessage(
    id: id,
    patientId: m['patientId'] ?? '',
    doctorId: m['doctorId'] ?? '',
    doctorName: m['doctorName'] ?? '',
    message: m['message'] ?? '',
    type: m['type'] ?? '',
    read: m['read'] ?? false,
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'doctorId': doctorId,
    'doctorName': doctorName,
    'message': message,
    'type': type,
    'read': read,
    'createdAt': FieldValue.serverTimestamp(),
  };
}