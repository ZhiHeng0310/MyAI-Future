import 'package:cloud_firestore/cloud_firestore.dart';

enum AppointmentStatus { pending, confirmed, cancelled, completed }

class AppointmentSlot {
  final String            id;
  final String            doctorId;
  final String            doctorName;
  final String            patientId;
  final String            patientName;
  final DateTime          date;
  final String            timeSlot;   // "HH:mm"
  final List<String>      symptoms;
  final AppointmentStatus status;
  final String?           notes;
  final DateTime          bookedAt;

  const AppointmentSlot({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.patientId,
    required this.patientName,
    required this.date,
    required this.timeSlot,
    required this.symptoms,
    required this.status,
    this.notes,
    required this.bookedAt,
  });

  /// Returns a human-readable date string "Mon, 2 Jan 2025"
  String get dateLabel {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final wd     = days[date.weekday - 1];
    return '$wd, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  factory AppointmentSlot.fromMap(Map<String, dynamic> m, String id) =>
      AppointmentSlot(
        id:          id,
        doctorId:    m['doctorId']    ?? '',
        doctorName:  m['doctorName']  ?? '',
        patientId:   m['patientId']   ?? '',
        patientName: m['patientName'] ?? '',
        date: m['date'] != null
            ? (m['date'] as Timestamp).toDate()
            : DateTime.now(),
        timeSlot: m['timeSlot'] ?? '09:00',
        symptoms: List<String>.from(m['symptoms'] ?? []),
        status: AppointmentStatus.values.firstWhere(
              (e) => e.name == m['status'],
          orElse: () => AppointmentStatus.pending,
        ),
        notes:    m['notes'],
        bookedAt: m['bookedAt'] != null
            ? (m['bookedAt'] as Timestamp).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
    'doctorId':    doctorId,
    'doctorName':  doctorName,
    'patientId':   patientId,
    'patientName': patientName,
    'date':        Timestamp.fromDate(date),
    'timeSlot':    timeSlot,
    'symptoms':    symptoms,
    'status':      status.name,
    'notes':       notes,
    'bookedAt':    FieldValue.serverTimestamp(),
  };
}

/// A doctor's available working hours and slot duration.
class DoctorSchedule {
  final String doctorId;
  final String startTime;   // "09:00"
  final String endTime;     // "17:00"
  final int    slotMinutes; // 30
  final List<int> workDays; // 1=Mon … 5=Fri

  const DoctorSchedule({
    required this.doctorId,
    this.startTime   = '09:00',
    this.endTime     = '17:00',
    this.slotMinutes = 30,
    this.workDays    = const [1, 2, 3, 4, 5],
  });

  /// Generate all possible time slots for a day.
  List<String> get allSlots {
    final slots = <String>[];
    final startH = int.parse(startTime.split(':')[0]);
    final startM = int.parse(startTime.split(':')[1]);
    final endH   = int.parse(endTime.split(':')[0]);
    final endM   = int.parse(endTime.split(':')[1]);
    var mins     = startH * 60 + startM;
    final endMins = endH * 60 + endM;
    while (mins + slotMinutes <= endMins) {
      final h = (mins ~/ 60).toString().padLeft(2, '0');
      final m = (mins % 60).toString().padLeft(2, '0');
      slots.add('$h:$m');
      mins += slotMinutes;
    }
    return slots;
  }
}

/// A doctor inbox message from AI system or doctor's AI reply.
class DoctorInboxMessage {
  final String   id;
  final String   doctorId;
  final String   patientId;
  final String   patientName;
  final String   message;
  final String   type;    // "health_alert" | "ai_relay" | "doctor_response"
  final String?  alertId;
  final bool     read;
  final DateTime createdAt;

  const DoctorInboxMessage({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.message,
    required this.type,
    this.alertId,
    required this.read,
    required this.createdAt,
  });

  factory DoctorInboxMessage.fromMap(Map<String, dynamic> m, String id) =>
      DoctorInboxMessage(
        id:          id,
        doctorId:    m['doctorId']    ?? '',
        patientId:   m['patientId']   ?? '',
        patientName: m['patientName'] ?? '',
        message:     m['message']     ?? '',
        type:        m['type']        ?? 'health_alert',
        alertId:     m['alertId'],
        read:        m['read']        ?? false,
        createdAt: m['createdAt'] != null
            ? (m['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
    'doctorId':    doctorId,
    'patientId':   patientId,
    'patientName': patientName,
    'message':     message,
    'type':        type,
    'alertId':     alertId,
    'read':        read,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}

/// A health alert created by the Patient AI.
class HealthAlert {
  final String   id;
  final String   patientId;
  final String   patientName;
  final String   doctorId;
  final String   message;
  final String   riskLevel; // "low" | "medium" | "high"
  final String   status;    // "pending" | "acknowledged" | "responded"
  final String?  doctorResponse;
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
    id:             id,
    patientId:      m['patientId']      ?? '',
    patientName:    m['patientName']     ?? '',
    doctorId:       m['doctorId']        ?? '',
    message:        m['message']         ?? '',
    riskLevel:      m['riskLevel']       ?? 'low',
    status:         m['status']          ?? 'pending',
    doctorResponse: m['doctorResponse'],
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'patientId':      patientId,
    'patientName':    patientName,
    'doctorId':       doctorId,
    'message':        message,
    'riskLevel':      riskLevel,
    'status':         status,
    'doctorResponse': doctorResponse,
    'createdAt':      FieldValue.serverTimestamp(),
  };
}