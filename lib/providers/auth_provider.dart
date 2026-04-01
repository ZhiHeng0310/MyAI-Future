import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/patient_model.dart';
import '../services/firestore_service.dart';

class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirestoreService();

  User? _user;
  PatientModel? _patient;
  bool _loading = false;
  String? _error;

  User? get user => _user;
  PatientModel? get patient => _patient;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  AuthProvider() {
    _auth.authStateChanges().listen((u) async {
      _user = u;
      if (u != null) await _loadPatient(u.uid);
      notifyListeners();
    });
  }

  Future<void> _loadPatient(String uid) async {
    _patient = await _db.getPatient(uid);
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = null;
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

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final patient = PatientModel(
        id: cred.user!.uid,
        name: name,
        email: email,
        phone: phone,
      );
      await _db.savePatient(patient);
      _patient = patient;
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _patient = null;
    notifyListeners();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':    return 'No account found with this email.';
      case 'wrong-password':    return 'Incorrect password.';
      case 'email-already-in-use': return 'Email already registered.';
      case 'weak-password':     return 'Password must be at least 6 characters.';
      default:                  return 'Authentication failed. Please try again.';
    }
  }
}
