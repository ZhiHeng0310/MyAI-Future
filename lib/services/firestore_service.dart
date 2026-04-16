import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/queue_model.dart';
import '../models/medication_model.dart';
import '../models/checkin_model.dart';
import '../models/appointment_model.dart';
// Import health_alert_model for HealthAlert used in health_alerts collection
import '../models/health_alert_model.dart' as ham;

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ─── Patient ──────────────────────────────────────────────────────────────

  Future<PatientModel?> getPatient(String uid) async {
    final doc = await _db.collection('patients').doc(uid).get();
    if (!doc.exists) return null;
    return PatientModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> savePatient(PatientModel p) =>
      _db.collection('patients').doc(p.id).set(p.toMap());

  Future<void> assignDoctor(String patientId, String doctorId) =>
      _db
          .collection('patients')
          .doc(patientId)
          .update({'assignedDoctorId': doctorId});

  Stream<List<PatientModel>> allPatientsStream() => _db
      .collection('patients')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => PatientModel.fromMap(d.data(), d.id)).toList());

  Future<List<PatientModel>> getPatientsForDoctor(String doctorId) async {
    final medSnap = await _db
        .collection('medications')
        .where('doctorId', isEqualTo: doctorId)
        .where('active', isEqualTo: true)
        .get();

    final patientIds = medSnap.docs
        .map((d) => d.data()['patientId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (patientIds.isEmpty) return [];

    final patients = await Future.wait(patientIds.map(getPatient));
    return patients.whereType<PatientModel>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Stream<List<PatientModel>> doctorPatientsStream(String doctorId) =>
      _db
          .collection('medications')
          .where('doctorId', isEqualTo: doctorId)
          .where('active', isEqualTo: true)
          .snapshots()
          .asyncMap((snap) async {
        final patientIds = snap.docs
            .map((d) => d.data()['patientId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        if (patientIds.isEmpty) return <PatientModel>[];

        final patients =
        await Future.wait(patientIds.map(getPatient));
        return patients.whereType<PatientModel>().toList()
          ..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  // ─── Doctor ───────────────────────────────────────────────────────────────

  Future<DoctorModel?> getDoctor(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    if (!doc.exists) return null;
    return DoctorModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> saveDoctor(DoctorModel d) =>
      _db.collection('doctors').doc(d.id).set(d.toMap());

  Future<List<DoctorModel>> getAllDoctors() async {
    final snap = await _db.collection('doctors').limit(10).get();
    return snap.docs
        .map((d) => DoctorModel.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<DoctorModel>> getDoctorsForPatient(String patientId) async {
    final medSnap = await _db
        .collection('medications')
        .where('patientId', isEqualTo: patientId)
        .where('active', isEqualTo: true)
        .get();

    final doctorIds = medSnap.docs
        .map((d) => d.data()['doctorId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (doctorIds.isEmpty) return [];

    final doctors = await Future.wait(doctorIds.map(getDoctor));
    return doctors.whereType<DoctorModel>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ─── Queue ────────────────────────────────────────────────────────────────

  Stream<List<QueueEntry>> queueStream(String clinicId) => _db
      .collection('queues')
      .doc(clinicId)
      .collection('entries')
      .orderBy('priority', descending: true)
      .orderBy('joinedAt')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => QueueEntry.fromMap(d.data(), d.id)).toList());

  Future<QueueEntry?> findActiveQueueEntry(
      String clinicId, String patientId) async {
    final snap = await _db
        .collection('queues')
        .doc(clinicId)
        .collection('entries')
        .where('patientId', isEqualTo: patientId)
        .get();
    final active = snap.docs
        .map((d) => QueueEntry.fromMap(d.data(), d.id))
        .where((e) => e.status != QueueStatus.done)
        .toList();
    return active.isEmpty ? null : active.first;
  }

  Future<QueueEntry> joinQueue({
    required String clinicId,
    required String patientId,
    required String patientName,
    required List<String> symptoms,
  }) async {
    final ref = _db
        .collection('queues')
        .doc(clinicId)
        .collection('entries')
        .doc();
    final entry = QueueEntry(
      id: ref.id,
      patientId: patientId,
      patientName: patientName,
      symptoms: symptoms,
      priority: _calcPriority(symptoms),
      status: QueueStatus.waiting,
      joinedAt: DateTime.now(),
    );
    await ref.set(entry.toMap());
    return entry;
  }

  Future<void> updateQueuePriority(
      String clinicId, String entryId, int priority) =>
      _db
          .collection('queues')
          .doc(clinicId)
          .collection('entries')
          .doc(entryId)
          .update({
        'priority': priority,
        'updatedAt': FieldValue.serverTimestamp()
      });

  Future<void> updateQueueStatus(
      String clinicId, String entryId, QueueStatus status) =>
      _db
          .collection('queues')
          .doc(clinicId)
          .collection('entries')
          .doc(entryId)
          .update({'status': status.name});

  Future<void> removeQueueEntry(String clinicId, String entryId) =>
      _db
          .collection('queues')
          .doc(clinicId)
          .collection('entries')
          .doc(entryId)
          .delete();

  int _calcPriority(List<String> symptoms) {
    const urgent = [
      'chest pain',
      'shortness of breath',
      'difficulty breathing',
      'severe pain',
      'unconscious'
    ];
    for (final s in symptoms) {
      if (urgent.any((u) => s.toLowerCase().contains(u))) return 10;
    }
    return 5;
  }

  // ─── Appointments ─────────────────────────────────────────────────────────

  Future<List<String>> getBookedSlots(String doctorId, DateTime date) async {
    final dateStr = _dateKey(date);
    final snap = await _db
        .collection('appointments')
        .doc(doctorId)
        .collection('slots')
        .where('dateKey', isEqualTo: dateStr)
        .where('status', whereIn: ['pending', 'confirmed'])
        .get();
    return snap.docs
        .map((d) => d.data()['timeSlot'] as String)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAvailableSlots(
      String doctorId, DateTime from, int count) async {
    final schedule = DoctorSchedule(doctorId: doctorId);
    final results = <Map<String, dynamic>>[];
    var checkDate = from;

    while (results.length < count) {
      if (schedule.workDays.contains(checkDate.weekday)) {
        final booked = await getBookedSlots(doctorId, checkDate);
        for (final slot in schedule.allSlots) {
          if (!booked.contains(slot)) {
            results.add({'date': checkDate, 'timeSlot': slot});
            if (results.length >= count) break;
          }
        }
      }
      checkDate = checkDate.add(const Duration(days: 1));
      if (checkDate.difference(from).inDays > 30) break;
    }
    return results;
  }

  Future<AppointmentSlot?> bookAppointment({
    required String doctorId,
    required String doctorName,
    required String patientId,
    required String patientName,
    required DateTime date,
    required String timeSlot,
    required List<String> symptoms,
  }) async {
    final dateStr = _dateKey(date);
    final booked = await getBookedSlots(doctorId, date);
    if (booked.contains(timeSlot)) return null;

    final ref = _db
        .collection('appointments')
        .doc(doctorId)
        .collection('slots')
        .doc();
    final appt = AppointmentSlot(
      id: ref.id,
      doctorId: doctorId,
      doctorName: doctorName,
      patientId: patientId,
      patientName: patientName,
      date: date,
      timeSlot: timeSlot,
      symptoms: symptoms,
      status: AppointmentStatus.confirmed,
      bookedAt: DateTime.now(),
    );
    final data = appt.toMap()..['dateKey'] = dateStr;
    await ref.set(data);
    return appt;
  }

  Future<void> cancelAppointment(String doctorId, String slotId) =>
      _db
          .collection('appointments')
          .doc(doctorId)
          .collection('slots')
          .doc(slotId)
          .update({'status': AppointmentStatus.cancelled.name});

  Stream<List<AppointmentSlot>> patientAppointmentsStream(
      String patientId) =>
      _db
          .collectionGroup('slots')
          .where('patientId', isEqualTo: patientId)
          .where('status', whereIn: ['pending', 'confirmed'])
          .orderBy('date')
          .snapshots()
          .map((s) => s.docs
          .map((d) => AppointmentSlot.fromMap(d.data(), d.id))
          .toList());

  Stream<List<AppointmentSlot>> doctorDayScheduleStream(
      String doctorId, DateTime date) =>
      _db
          .collection('appointments')
          .doc(doctorId)
          .collection('slots')
          .where('dateKey', isEqualTo: _dateKey(date))
          .where('status', whereIn: ['pending', 'confirmed'])
          .orderBy('timeSlot')
          .snapshots()
          .map((s) => s.docs
          .map((d) => AppointmentSlot.fromMap(d.data(), d.id))
          .toList());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── Health Alerts — uses health_alert_model.HealthAlert ─────────────────

  /// Creates a health alert. Uses [ham.HealthAlert] from health_alert_model.
  Future<String> createHealthAlert(ham.HealthAlert alert) async {
    final ref = _db.collection('health_alerts').doc();
    await ref.set(alert.toMap());

    // Also create doctor inbox message (uses appointment_model.DoctorInboxMessage)
    await createDoctorInboxMessage(DoctorInboxMessage(
      id: '',
      doctorId: alert.doctorId,
      patientId: alert.patientId,
      patientName: alert.patientName,
      message:
      '🚨 Health alert (${alert.riskLevel.toUpperCase()} risk): ${alert.message}',
      type: 'health_alert',
      alertId: ref.id,
      read: false,
      createdAt: DateTime.now(),
    ));

    return ref.id;
  }

  Future<void> respondToAlert(
      String alertId, String doctorResponse, String status) =>
      _db.collection('health_alerts').doc(alertId).update({
        'doctorResponse': doctorResponse,
        'status': status,
        'respondedAt': FieldValue.serverTimestamp(),
      });

  /// Stream of alerts for doctor alerts screen (uses ham.HealthAlert)
  Stream<List<ham.HealthAlert>> doctorAlertsStream(String doctorId) => _db
      .collection('health_alerts')
      .where('doctorId', isEqualTo: doctorId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs
      .map((d) => ham.HealthAlert.fromMap(d.data(), d.id))
      .toList());

  /// Fetch alerts within [within] duration (default 24 hours)
  Future<List<ham.HealthAlert>> getRecentAlertsForDoctor(
      String doctorId, {
        Duration within = const Duration(hours: 24),
      }) async {
    final cutoff = DateTime.now().subtract(within);
    final snap = await _db
        .collection('health_alerts')
        .where('doctorId', isEqualTo: doctorId)
        .where('createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .get();

    return snap.docs
        .map((d) => ham.HealthAlert.fromMap(d.data(), d.id))
        .toList();
  }

  Future<int> unreadAlertCount(String doctorId) async {
    final snap = await _db
        .collection('health_alerts')
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─── Doctor Inbox — uses appointment_model.DoctorInboxMessage ─────────────

  Future<void> createDoctorInboxMessage(DoctorInboxMessage msg) async {
    final ref = _db
        .collection('doctor_inbox')
        .doc(msg.doctorId)
        .collection('messages')
        .doc();
    await ref.set(msg.toMap());
  }

  Stream<List<DoctorInboxMessage>> doctorInboxStream(String doctorId) => _db
      .collection('doctor_inbox')
      .doc(doctorId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs
      .map((d) => DoctorInboxMessage.fromMap(d.data(), d.id))
      .toList());

  Future<void> markInboxRead(String doctorId, String messageId) =>
      _db
          .collection('doctor_inbox')
          .doc(doctorId)
          .collection('messages')
          .doc(messageId)
          .update({'read': true});

  // ─── Patient Inbox ────────────────────────────────────────────────────────

  Future<void> createPatientInboxMessage({
    required String patientId,
    required String message,
    required String type,
    String? doctorId,
  }) =>
      _db
          .collection('patient_inbox')
          .doc(patientId)
          .collection('messages')
          .add({
        'patientId': patientId,
        'message': message,
        'type': type,
        'doctorId': doctorId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<List<Map<String, dynamic>>> patientInboxStream(
      String patientId) =>
      _db
          .collection('patient_inbox')
          .doc(patientId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((s) =>
          s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  // ─── Medications ──────────────────────────────────────────────────────────

  Stream<List<Medication>> medicationsStream(String patientId) => _db
      .collection('medications')
      .where('patientId', isEqualTo: patientId)
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => Medication.fromMap(d.data(), d.id)).toList());

  Future<List<Medication>> getMedicationsForPatient(
      String patientId) async {
    final snap = await _db
        .collection('medications')
        .where('patientId', isEqualTo: patientId)
        .where('active', isEqualTo: true)
        .get();
    return snap.docs
        .map((d) => Medication.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<Medication>> getMedicationsForPatientAndDoctor(
      String patientId, String doctorId) async {
    final snap = await _db
        .collection('medications')
        .where('patientId', isEqualTo: patientId)
        .where('doctorId', isEqualTo: doctorId)
        .where('active', isEqualTo: true)
        .get();
    return snap.docs
        .map((d) => Medication.fromMap(d.data(), d.id))
        .toList();
  }

  /// All active medications — used by DoctorChatProvider to find prescriptions
  Future<List<Medication>> getAllMedications() async {
    final snap = await _db
        .collection('medications')
        .where('active', isEqualTo: true)
        .get();
    return snap.docs
        .map((d) => Medication.fromMap(d.data(), d.id))
        .toList();
  }

  Stream<List<Medication>> medicationsStreamForDoctor(
      String patientId, String doctorId) =>
      _db
          .collection('medications')
          .where('patientId', isEqualTo: patientId)
          .where('doctorId', isEqualTo: doctorId)
          .where('active', isEqualTo: true)
          .snapshots()
          .map((s) => s.docs
          .map((d) => Medication.fromMap(d.data(), d.id))
          .toList());

  Future<String> addMedication(Medication med, {String? doctorId}) async {
    final ref = _db.collection('medications').doc();
    await ref.set(Medication(
      id: ref.id,
      patientId: med.patientId,
      doctorId: doctorId ?? med.doctorId,
      name: med.name,
      dosage: med.dosage,
      frequency: med.frequency,
      reminderTimes: med.reminderTimes,
      active: true,
    ).toMap());

    if (doctorId != null && doctorId.isNotEmpty) {
      await assignDoctor(med.patientId, doctorId);
    }

    return ref.id;
  }

  Future<void> deactivateMedication(String medId) =>
      _db
          .collection('medications')
          .doc(medId)
          .update({'active': false});

  Future<void> logDoseForSlot(
      String medicationId, String timeSlot, bool taken) async {
    final slotKey = Medication.slotKey(timeSlot);
    if (taken) {
      await _db.collection('medications').doc(medicationId).update({
        'takenSlots': FieldValue.arrayUnion([slotKey]),
        'lastTaken': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('medications').doc(medicationId).update({
        'takenSlots': FieldValue.arrayRemove([slotKey]),
      });
    }
    await _db.collection('dose_logs').add({
      'medicationId': medicationId,
      'timeSlot': timeSlot,
      'slotKey': slotKey,
      'taken': taken,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.collection('dose_logs').add({
      'medicationId': medicationId,
      'taken': taken,
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (taken) {
      await _db
          .collection('medications')
          .doc(medicationId)
          .update({'lastTaken': FieldValue.serverTimestamp()});
    }
  }

  // ─── Check-ins ────────────────────────────────────────────────────────────

  Future<void> saveCheckIn(CheckIn c) =>
      _db.collection('checkins').add(c.toMap());

  // ─── Legacy alerts ────────────────────────────────────────────────────────

  Future<void> createAlert({
    required String patientId,
    required String type,
    required String message,
    String? clinicId,
  }) =>
      _db.collection('alerts').add({
        'patientId': patientId,
        'type': type,
        'message': message,
        'clinicId': clinicId,
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
}