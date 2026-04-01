import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';
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

  // ─── Queue ────────────────────────────────────────────────────────────────

  Stream<List<QueueEntry>> queueStream(String clinicId) {
    return _db
        .collection('queues')
        .doc(clinicId)
        .collection('entries')
        .orderBy('priority', descending: true)
        .orderBy('joinedAt')
        .snapshots()
        .map((s) => s.docs.map((d) => QueueEntry.fromMap(d.data(), d.id)).toList());
  }

  Future<QueueEntry> joinQueue({
    required String clinicId,
    required String patientId,
    required String patientName,
    required List<String> symptoms,
  }) async {
    final ref = _db.collection('queues').doc(clinicId).collection('entries').doc();
    final entry = QueueEntry(
      id: ref.id,
      patientId: patientId,
      patientName: patientName,
      symptoms: symptoms,
      priority: _calculatePriority(symptoms),
      status: QueueStatus.waiting,
      joinedAt: DateTime.now(),
    );
    await ref.set(entry.toMap());
    return entry;
  }

  Future<void> updateQueuePriority(String clinicId, String entryId, int priority) =>
      _db.collection('queues').doc(clinicId).collection('entries').doc(entryId)
          .update({'priority': priority, 'updatedAt': FieldValue.serverTimestamp()});

  int _calculatePriority(List<String> symptoms) {
    const highUrgency = ['chest pain', 'difficulty breathing', 'severe pain', 'unconscious'];
    for (final s in symptoms) {
      if (highUrgency.any((h) => s.toLowerCase().contains(h))) return 10;
    }
    return 5;
  }

  // ─── Medications ─────────────────────────────────────────────────────────

  Stream<List<Medication>> medicationsStream(String patientId) {
    return _db
        .collection('medications')
        .where('patientId', isEqualTo: patientId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Medication.fromMap(d.data(), d.id)).toList());
  }

  Future<void> logDose(String medicationId, bool taken) async {
    final log = {
      'medicationId': medicationId,
      'taken': taken,
      'timestamp': FieldValue.serverTimestamp(),
    };
    await _db.collection('dose_logs').add(log);
    if (taken) {
      await _db.collection('medications').doc(medicationId)
          .update({'lastTaken': FieldValue.serverTimestamp()});
    }
  }

  // ─── Check-ins ────────────────────────────────────────────────────────────

  Future<void> saveCheckIn(CheckIn checkIn) =>
      _db.collection('checkins').add(checkIn.toMap());

  Stream<List<CheckIn>> checkInsStream(String patientId) {
    return _db
        .collection('checkins')
        .where('patientId', isEqualTo: patientId)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((s) => s.docs.map((d) => CheckIn.fromMap(d.data(), d.id)).toList());
  }

  // ─── Alerts ───────────────────────────────────────────────────────────────

  Future<void> createAlert({
    required String patientId,
    required String type,
    required String message,
    String? clinicId,
  }) async {
    await _db.collection('alerts').add({
      'patientId': patientId,
      'type': type,
      'message': message,
      'clinicId': clinicId,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
