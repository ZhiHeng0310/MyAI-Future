import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/queue_model.dart';
import '../models/medication_model.dart';
import '../models/checkin_model.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ─── Patient ──────────────────────────────────────────────────────────────

  Future<PatientModel?> getPatient(String uid) async {
    final doc = await _db.collection('patients').doc(uid).get();
    if (!doc.exists) return null;
    return PatientModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> savePatient(PatientModel patient) =>
      _db.collection('patients').doc(patient.id).set(patient.toMap());

  Stream<List<PatientModel>> allPatientsStream() => _db
      .collection('patients')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => PatientModel.fromMap(d.data(), d.id)).toList());

  // ─── Doctor ───────────────────────────────────────────────────────────────

  Future<DoctorModel?> getDoctor(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    if (!doc.exists) return null;
    return DoctorModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> saveDoctor(DoctorModel doctor) =>
      _db.collection('doctors').doc(doctor.id).set(doctor.toMap());

  // ─── Queue ────────────────────────────────────────────────────────────────

  /// Live stream of queue entries ordered by priority desc, joinedAt asc.
  /// Requires composite index: priority DESC + joinedAt ASC on "entries" collection.
  Stream<List<QueueEntry>> queueStream(String clinicId) => _db
      .collection('queues')
      .doc(clinicId)
      .collection('entries')
      .orderBy('priority', descending: true)
      .orderBy('joinedAt')
      .snapshots()
      .map((s) =>
      s.docs.map((d) => QueueEntry.fromMap(d.data(), d.id)).toList());

  /// Finds an existing ACTIVE (not done) queue entry for this patient.
  /// Used on login to restore state across app restarts.
  Future<QueueEntry?> findActiveQueueEntry(
      String clinicId, String patientId) async {
    // Query by patientId only (no compound query = no composite index needed)
    final snap = await _db
        .collection('queues')
        .doc(clinicId)
        .collection('entries')
        .where('patientId', isEqualTo: patientId)
        .get();

    // Filter out 'done' entries in Dart
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
      id:          ref.id,
      patientId:   patientId,
      patientName: patientName,
      symptoms:    symptoms,
      priority:    _calculatePriority(symptoms),
      status:      QueueStatus.waiting,
      joinedAt:    DateTime.now(),
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
        'priority':  priority,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateQueueStatus(
      String clinicId, String entryId, QueueStatus status) =>
      _db
          .collection('queues')
          .doc(clinicId)
          .collection('entries')
          .doc(entryId)
          .update({'status': status.name});

  Future<void> removeQueueEntry(String clinicId, String entryId) => _db
      .collection('queues')
      .doc(clinicId)
      .collection('entries')
      .doc(entryId)
      .delete();

  int _calculatePriority(List<String> symptoms) {
    const highUrgency = [
      'chest pain',
      'shortness of breath',
      'difficulty breathing',
      'severe pain',
      'unconscious',
    ];
    for (final s in symptoms) {
      if (highUrgency.any((h) => s.toLowerCase().contains(h))) return 10;
    }
    return 5;
  }

  // ─── Medications ──────────────────────────────────────────────────────────

  Stream<List<Medication>> medicationsStream(String patientId) => _db
      .collection('medications')
      .where('patientId', isEqualTo: patientId)
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => Medication.fromMap(d.data(), d.id)).toList());

  Future<String> addMedication(Medication medication) async {
    final ref = _db.collection('medications').doc();
    final med = Medication(
      id:            ref.id,
      patientId:     medication.patientId,
      name:          medication.name,
      dosage:        medication.dosage,
      frequency:     medication.frequency,
      reminderTimes: medication.reminderTimes,
      active:        true,
    );
    await ref.set(med.toMap());
    return ref.id;
  }

  Future<void> deactivateMedication(String medId) =>
      _db.collection('medications').doc(medId).update({'active': false});

  Future<void> logDose(String medicationId, bool taken) async {
    await _db.collection('dose_logs').add({
      'medicationId': medicationId,
      'taken':        taken,
      'timestamp':    FieldValue.serverTimestamp(),
    });
    if (taken) {
      await _db
          .collection('medications')
          .doc(medicationId)
          .update({'lastTaken': FieldValue.serverTimestamp()});
    }
  }

  // ─── Check-ins ────────────────────────────────────────────────────────────

  Future<void> saveCheckIn(CheckIn checkIn) =>
      _db.collection('checkins').add(checkIn.toMap());

  Stream<List<CheckIn>> checkInsStream(String patientId) => _db
      .collection('checkins')
      .where('patientId', isEqualTo: patientId)
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((s) =>
      s.docs.map((d) => CheckIn.fromMap(d.data(), d.id)).toList());

  // ─── Alerts ───────────────────────────────────────────────────────────────

  Future<void> createAlert({
    required String patientId,
    required String type,
    required String message,
    String? clinicId,
  }) async {
    await _db.collection('alerts').add({
      'patientId': patientId,
      'type':      type,
      'message':   message,
      'clinicId':  clinicId,
      'resolved':  false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}