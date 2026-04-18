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

        // Only save FCM token after profile is loaded and exists
        if (_role != 'unknown') {
          Future(() async {
            try {
              await NotificationService.init();
              final collection = _role == 'doctor' ? 'doctors' : 'patient';
              await NotificationService.saveFcmToken(u.uid, collection);
            } catch (e) {
              debugPrint('FCM token save non-critical error: $e');
            }
          });
        }

        _profileLoading = false;
        notifyListeners();
      } else {
        _patient = null;
        _doctor = null;
        _role = 'unknown';
        _profileLoading = false;

        notifyListeners();
      }
    });
  }

  // ─── Profile loader ───────────────────────────────────────────────────────
  Future<void> _loadProfile(String uid) async {
    try {
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
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  // ─── Sign in ──────────────────────────────────────────────────────────────
  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      debugPrint('Attempting sign in for: $email');
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      debugPrint('Sign in successful');
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign in error: ${e.code} - ${e.message}');
      _error = _friendlyError(e.code);
      return false;
    } catch (e) {
      debugPrint('Unexpected sign in error: $e');
      _error = 'An unexpected error occurred. Please try again.';
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

    debugPrint('=== Starting Patient Registration ===');
    debugPrint('Email: $email');
    debugPrint('Name: $name');

    try {
      // Step 1: Create Firebase Auth user
      debugPrint('Step 1: Creating Firebase Auth user...');
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('Auth user created with UID: ${cred.user!.uid}');

      // Step 2: Create patient model
      final patient = PatientModel(
        id: cred.user!.uid,
        name: name,
        email: email,
        phone: phone,
      );

      try {
        // Step 3: Save to Firestore
        debugPrint('Step 2: Saving patient to Firestore...');
        await _db.savePatient(patient);
        debugPrint('Patient saved to Firestore successfully');

        // Step 4: Wait for Firestore to propagate
        debugPrint('Step 3: Waiting for Firestore propagation...');
        await Future.delayed(const Duration(milliseconds: 500));

        // Step 5: Verify document exists
        debugPrint('Step 4: Verifying document exists...');
        final verifyDoc = await _db.getPatient(cred.user!.uid);
        if (verifyDoc == null) {
          throw Exception('Failed to verify patient document creation');
        }
        debugPrint('Document verified successfully');

      } catch (e) {
        debugPrint('Error saving patient: $e');
        // Rollback: Delete auth user
        debugPrint('Rolling back: Deleting auth user...');
        await cred.user?.delete();
        _error = 'Failed to create profile. Please try again.';
        return false;
      }

      _patient = patient;
      _role = 'patient';

      debugPrint('=== Patient Registration Complete ===');
      return true;

    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth error: ${e.code} - ${e.message}');
      _error = _friendlyError(e.code);
      return false;
    } catch (e) {
      debugPrint('Unexpected registration error: $e');
      _error = 'Registration failed. Please try again.';
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
    // Validate clinic code first
    if (clinicCode.trim().toUpperCase() != 'CARELOOP-DOC-2024') {
      _error = 'Invalid clinic registration code.';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    debugPrint('=== Starting Doctor Registration ===');
    debugPrint('Email: $email');
    debugPrint('Name: $name');
    debugPrint('Doctor ID: $doctorId');

    try {
      // Step 1: Create Firebase Auth user
      debugPrint('Step 1: Creating Firebase Auth user...');
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('Auth user created with UID: ${cred.user!.uid}');

      // Step 2: Create doctor model
      final doctor = DoctorModel(
        id: cred.user!.uid,
        name: name,
        email: email,
        doctorId: doctorId,
        specialization: specialization,
      );

      try {
        // Step 3: Save to Firestore
        debugPrint('Step 2: Saving doctor to Firestore...');
        await _db.saveDoctor(doctor);
        debugPrint('Doctor saved to Firestore successfully');

        // Step 4: Wait for Firestore to propagate
        debugPrint('Step 3: Waiting for Firestore propagation...');
        await Future.delayed(const Duration(milliseconds: 500));

        // Step 5: Verify document exists
        debugPrint('Step 4: Verifying document exists...');
        final verifyDoc = await _db.getDoctor(cred.user!.uid);
        if (verifyDoc == null) {
          throw Exception('Failed to verify doctor document creation');
        }
        debugPrint('Document verified successfully');

      } catch (e) {
        debugPrint('Error saving doctor: $e');
        // Rollback: Delete auth user
        debugPrint('Rolling back: Deleting auth user...');
        await cred.user?.delete();
        _error = 'Failed to create doctor profile.';
        return false;
      }

      _doctor = doctor;
      _role = 'doctor';

      debugPrint('=== Doctor Registration Complete ===');
      return true;

    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth error: ${e.code} - ${e.message}');
      _error = _friendlyError(e.code);
      return false;
    } catch (e) {
      debugPrint('Unexpected registration error: $e');
      _error = 'Registration failed. Please try again.';
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
      case 'invalid-email':         return 'Invalid email address.';
      case 'operation-not-allowed': return 'Registration is currently disabled. Please contact support.';
      case 'network-request-failed': return 'Network error. Please check your connection.';
      default:                      return 'Authentication failed: $code';
    }
  }
}