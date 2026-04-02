import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/queue_model.dart';
import '../models/medication_model.dart';
import '../models/checkin_model.dart';
import '../models/appointment_model.dart';

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

  /// Assigns a doctor to a patient (called when doctor adds first medication).
  Future<void> assignDoctor(String patientId, String doctorId) =>
      _db.collection('patients').doc(patientId)
          .update({'assignedDoctorId': doctorId});

  Stream<List<PatientModel>> allPatientsStream() => _db
      .collection('patients')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => PatientModel.fromMap(d.data(), d.id)).toList());

  Future<List<PatientModel>> getPatientsForDoctor(String doctorId) async {
    final snap = await _db
        .collection('patients')
        .where('assignedDoctorId', isEqualTo: doctorId)
        .get();
    return snap.docs
        .map((d) => PatientModel.fromMap(d.data(), d.id))
        .toList();
  }

  // ─── Doctor ───────────────────────────────────────────────────────────────

  Future<DoctorModel?> getDoctor(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    if (!doc.exists) return null;
    return DoctorModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> saveDoctor(DoctorModel d) =>
      _db.collection('doctors').doc(d.id).set(d.toMap());

  // ─── Queue ────────────────────────────────────────────────────────────────

  Stream<List<QueueEntry>> queueStream(String clinicId) => _db
      .collection('queues').doc(clinicId).collection('entries')
      .orderBy('priority', descending: true)
      .orderBy('joinedAt')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => QueueEntry.fromMap(d.data(), d.id)).toList());

  Future<QueueEntry?> findActiveQueueEntry(
      String clinicId, String patientId) async {
    final snap = await _db
        .collection('queues').doc(clinicId).collection('entries')
        .where('patientId', isEqualTo: patientId)
        .get();
    final active = snap.docs
        .map((d) => QueueEntry.fromMap(d.data(), d.id))
        .where((e) => e.status != QueueStatus.done)
        .toList();
    return active.isEmpty ? null : active.first;
  }

  Future<QueueEntry> joinQueue({
    required String       clinicId,
    required String       patientId,
    required String       patientName,
    required List<String> symptoms,
  }) async {
    final ref = _db.collection('queues').doc(clinicId)
        .collection('entries').doc();
    final entry = QueueEntry(
      id: ref.id, patientId: patientId, patientName: patientName,
      symptoms: symptoms, priority: _calcPriority(symptoms),
      status: QueueStatus.waiting, joinedAt: DateTime.now(),
    );
    await ref.set(entry.toMap());
    return entry;
  }

  Future<void> updateQueuePriority(
      String clinicId, String entryId, int priority) =>
      _db.collection('queues').doc(clinicId).collection('entries')
          .doc(entryId).update(
          {'priority': priority, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> updateQueueStatus(
      String clinicId, String entryId, QueueStatus status) =>
      _db.collection('queues').doc(clinicId).collection('entries')
          .doc(entryId).update({'status': status.name});

  Future<void> removeQueueEntry(String clinicId, String entryId) =>
      _db.collection('queues').doc(clinicId)
          .collection('entries').doc(entryId).delete();

  int _calcPriority(List<String> symptoms) {
    const urgent = ['chest pain','shortness of breath',
      'difficulty breathing','severe pain','unconscious'];
    for (final s in symptoms) {
      if (urgent.any((u) => s.toLowerCase().contains(u))) return 10;
    }
    return 5;
  }

  // ─── Appointments ─────────────────────────────────────────────────────────

  /// Returns all booked (non-cancelled) slots for a doctor on a given date.
  Future<List<String>> getBookedSlots(String doctorId, DateTime date) async {
    final dateStr = _dateKey(date);
    final snap    = await _db
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

  /// Returns the next [count] available slots after [from] for a doctor.
  /// Used to suggest alternatives when a slot is taken.
  Future<List<Map<String, dynamic>>> getAvailableSlots(
      String doctorId, DateTime from, int count) async {
    final schedule = DoctorSchedule(doctorId: doctorId);
    final results  = <Map<String, dynamic>>[];
    var   checkDate = from;

    while (results.length < count) {
      // Skip weekends if not in workDays
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
      // Safety: don't search more than 30 days
      if (checkDate.difference(from).inDays > 30) break;
    }
    return results;
  }

  /// Book a slot — returns the new appointment or null if already taken.
  Future<AppointmentSlot?> bookAppointment({
    required String       doctorId,
    required String       doctorName,
    required String       patientId,
    required String       patientName,
    required DateTime     date,
    required String       timeSlot,
    required List<String> symptoms,
  }) async {
    final dateStr = _dateKey(date);

    // Atomic check-and-write using a transaction
    AppointmentSlot? result;
    await _db.runTransaction((tx) async {
      final existing = await tx.get(
        _db.collection('appointments').doc(doctorId)
            .collection('slots')
            .where('dateKey', isEqualTo: dateStr)
            .where('timeSlot', isEqualTo: timeSlot)
            .where('status', whereIn: ['pending', 'confirmed'])
            .limit(1) as DocumentReference, // workaround: query in tx
      );
      // Since Firestore transactions can't query, we check manually below
    });

    // Simpler approach: check then write (acceptable for clinic scheduling)
    final booked = await getBookedSlots(doctorId, date);
    if (booked.contains(timeSlot)) return null; // slot taken

    final ref  = _db.collection('appointments').doc(doctorId)
        .collection('slots').doc();
    final appt = AppointmentSlot(
      id:          ref.id,
      doctorId:    doctorId,
      doctorName:  doctorName,
      patientId:   patientId,
      patientName: patientName,
      date:        date,
      timeSlot:    timeSlot,
      symptoms:    symptoms,
      status:      AppointmentStatus.confirmed,
      bookedAt:    DateTime.now(),
    );
    final data = appt.toMap()..['dateKey'] = dateStr;
    await ref.set(data);
    result = appt;
    return result;
  }

  Future<void> cancelAppointment(String doctorId, String slotId) =>
      _db.collection('appointments').doc(doctorId)
          .collection('slots').doc(slotId)
          .update({'status': AppointmentStatus.cancelled.name});

  /// Patient's upcoming appointments (across all doctors).
  Stream<List<AppointmentSlot>> patientAppointmentsStream(String patientId) =>
      _db.collectionGroup('slots')
          .where('patientId', isEqualTo: patientId)
          .where('status', whereIn: ['pending', 'confirmed'])
          .orderBy('date')
          .snapshots()
          .map((s) => s.docs
          .map((d) => AppointmentSlot.fromMap(d.data(), d.id))
          .toList());

  /// Doctor's appointment list for a specific date.
  Stream<List<AppointmentSlot>> doctorDayScheduleStream(
      String doctorId, DateTime date) =>
      _db.collection('appointments').doc(doctorId)
          .collection('slots')
          .where('dateKey', isEqualTo: _dateKey(date))
          .where('status', whereIn: ['pending', 'confirmed'])
          .orderBy('timeSlot')
          .snapshots()
          .map((s) => s.docs
          .map((d) => AppointmentSlot.fromMap(d.data(), d.id))
          .toList());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  // ─── Health alerts ────────────────────────────────────────────────────────

  Future<String> createHealthAlert(HealthAlert alert) async {
    final ref = _db.collection('health_alerts').doc();
    await ref.set(alert.toMap());
    // Also push to doctor's inbox
    await createDoctorInboxMessage(DoctorInboxMessage(
      id:          '',
      doctorId:    alert.doctorId,
      patientId:   alert.patientId,
      patientName: alert.patientName,
      message:     '🚨 Health alert: ${alert.message}',
      type:        'health_alert',
      alertId:     ref.id,
      read:        false,
      createdAt:   DateTime.now(),
    ));
    return ref.id;
  }

  Future<void> respondToAlert(
      String alertId, String doctorResponse, String status) =>
      _db.collection('health_alerts').doc(alertId).update({
        'doctorResponse': doctorResponse,
        'status':         status,
        'respondedAt':    FieldValue.serverTimestamp(),
      });

  Stream<List<HealthAlert>> doctorAlertsStream(String doctorId) => _db
      .collection('health_alerts')
      .where('doctorId', isEqualTo: doctorId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => HealthAlert.fromMap(d.data(), d.id)).toList());

  Future<int> unreadAlertCount(String doctorId) async {
    final snap = await _db
        .collection('health_alerts')
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─── Doctor inbox ─────────────────────────────────────────────────────────

  Future<void> createDoctorInboxMessage(DoctorInboxMessage msg) async {
    final ref = _db.collection('doctor_inbox').doc(msg.doctorId)
        .collection('messages').doc();
    await ref.set(msg.toMap());
  }

  Stream<List<DoctorInboxMessage>> doctorInboxStream(String doctorId) => _db
      .collection('doctor_inbox').doc(doctorId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => DoctorInboxMessage.fromMap(d.data(), d.id)).toList());

  Future<void> markInboxRead(String doctorId, String messageId) =>
      _db.collection('doctor_inbox').doc(doctorId)
          .collection('messages').doc(messageId)
          .update({'read': true});

  // ─── Patient inbox (AI messages from doctor) ──────────────────────────────

  Future<void> createPatientInboxMessage({
    required String patientId,
    required String message,
    required String type,   // "appointment_request" | "doctor_note"
    String? doctorId,
  }) =>
      _db.collection('patient_inbox').doc(patientId)
          .collection('messages').add({
        'patientId': patientId,
        'message':   message,
        'type':      type,
        'doctorId':  doctorId,
        'read':      false,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<List<Map<String, dynamic>>> patientInboxStream(String patientId) =>
      _db.collection('patient_inbox').doc(patientId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((s) => s.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList());

  // ─── Medications ──────────────────────────────────────────────────────────

  Stream<List<Medication>> medicationsStream(String patientId) => _db
      .collection('medications')
      .where('patientId', isEqualTo: patientId)
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => Medication.fromMap(d.data(), d.id)).toList());

  Future<String> addMedication(Medication med, {String? doctorId}) async {
    final ref = _db.collection('medications').doc();
    await ref.set(Medication(
      id:            ref.id,
      patientId:     med.patientId,
      name:          med.name,
      dosage:        med.dosage,
      frequency:     med.frequency,
      reminderTimes: med.reminderTimes,
      active:        true,
    ).toMap());

    // Assign doctor to patient if provided and not yet assigned
    if (doctorId != null) {
      final patient = await getPatient(med.patientId);
      if (patient != null && patient.assignedDoctorId == null) {
        await assignDoctor(med.patientId, doctorId);
      }
    }
    return ref.id;
  }

  Future<void> deactivateMedication(String medId) =>
      _db.collection('medications').doc(medId).update({'active': false});

  Future<void> logDoseForSlot(
      String medicationId, String timeSlot, bool taken) async {
    final slotKey = Medication.slotKey(timeSlot);
    if (taken) {
      await _db.collection('medications').doc(medicationId).update({
        'takenSlots': FieldValue.arrayUnion([slotKey]),
        'lastTaken':  FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('medications').doc(medicationId).update({
        'takenSlots': FieldValue.arrayRemove([slotKey]),
      });
    }
    await _db.collection('dose_logs').add({
      'medicationId': medicationId,
      'timeSlot':     timeSlot,
      'slotKey':      slotKey,
      'taken':        taken,
      'timestamp':    FieldValue.serverTimestamp(),
    });
  }

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.collection('dose_logs').add({
      'medicationId': medicationId,
      'taken':        taken,
      'timestamp':    FieldValue.serverTimestamp(),
    });
    if (taken) {
      await _db.collection('medications').doc(medicationId)
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
        'patientId': patientId, 'type': type, 'message': message,
        'clinicId':  clinicId,  'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
}