import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db   = FirestoreService();

  User?         _user;
  PatientModel? _patient;
  DoctorModel?  _doctor;

  String _role           = 'unknown';
  bool   _profileLoading = false;
  bool   _loading        = false;
  String? _error;

  User?         get user           => _user;
  PatientModel? get patient        => _patient;
  DoctorModel?  get doctor         => _doctor;
  bool          get isLoggedIn     => _user != null;
  bool          get isDoctor       => _role == 'doctor';
  bool          get profileLoading => _profileLoading;
  bool          get loading        => _loading;
  String?       get error          => _error;

  AuthProvider() {
    _auth.authStateChanges().listen((u) async {
      _user = u;
      if (u != null) {
        _profileLoading = true;
        notifyListeners();
        await _loadProfile(u.uid);

        // ── Save FCM token for push notifications ──────────────────────────
        await NotificationService.init();
        final collection = _role == 'doctor' ? 'doctors' : 'patients';
        await NotificationService.saveFcmToken(u.uid, collection);

        _profileLoading = false;
      } else {
        _patient        = null;
        _doctor         = null;
        _role           = 'unknown';
        _profileLoading = false;
      }
      notifyListeners();
    });
  }

  // ─── Profile loader ───────────────────────────────────────────────────────
  Future<void> _loadProfile(String uid) async {
    final doc = await _db.getDoctor(uid);
    if (doc != null) {
      _doctor = doc;
      _role   = 'doctor';
      return;
    }
    final patient = await _db.getPatient(uid);
    if (patient != null) {
      _patient = patient;
      _role    = 'patient';
    }
  }

  // ─── Sign in ──────────────────────────────────────────────────────────────
  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Register patient ─────────────────────────────────────────────────────
  Future<bool> registerPatient({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final patient = PatientModel(
          id: cred.user!.uid, name: name, email: email, phone: phone);
      await _db.savePatient(patient);
      _patient = patient;
      _role    = 'patient';
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Register doctor ──────────────────────────────────────────────────────
  Future<bool> registerDoctor({
    required String email,
    required String password,
    required String name,
    required String doctorId,
    required String clinicCode,
    String? specialization,
  }) async {
    if (clinicCode.trim().toUpperCase() != 'CARELOOP-DOC-2024') {
      _error = 'Invalid clinic registration code.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final doctor = DoctorModel(
        id:             cred.user!.uid,
        name:           name,
        email:          email,
        doctorId:       doctorId,
        specialization: specialization,
      );
      await _db.saveDoctor(doctor);
      _doctor = doctor;
      _role   = 'doctor';
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Sign out ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ─── Error messages ───────────────────────────────────────────────────────
  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':        return 'No account found with this email.';
      case 'wrong-password':        return 'Incorrect password.';
      case 'invalid-credential':    return 'Incorrect email or password.';
      case 'email-already-in-use':  return 'Email already registered.';
      case 'weak-password':         return 'Password must be at least 6 characters.';
      default:                      return 'Authentication failed. Please try again.';
    }
  }
}