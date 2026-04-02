import 'package:flutter/material.dart';
import '../models/appointment_model.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class AppointmentProvider extends ChangeNotifier {
  final _db = FirestoreService();

  List<AppointmentSlot> _myAppointments = [];
  bool _loading = false;
  String? _error;

  List<AppointmentSlot> get myAppointments => _myAppointments;
  bool    get loading => _loading;
  String? get error   => _error;

  void startListening(String patientId) {
    _db.patientAppointmentsStream(patientId).listen((appts) {
      _myAppointments = appts;
      notifyListeners();
    });
  }

  /// Book an appointment. Returns null if slot is taken, or the booked slot.
  Future<BookingResult> bookAppointment({
    required DoctorModel  doctor,
    required PatientModel patient,
    required DateTime     date,
    required String       timeSlot,
    required List<String> symptoms,
  }) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      // 1. Attempt to book
      final appt = await _db.bookAppointment(
        doctorId:    doctor.id,
        doctorName:  doctor.name,
        patientId:   patient.id,
        patientName: patient.name,
        date:        date,
        timeSlot:    timeSlot,
        symptoms:    symptoms,
      );

      if (appt != null) {
        // Success — send notifications
        await NotificationService.showQueueStatusNotification(
          title: '✅ Appointment confirmed',
          body:  'Your appointment with Dr. ${doctor.name} '
              'on ${appt.dateLabel} at $timeSlot is confirmed.',
        );
        return BookingResult.success(appt);
      }

      // Slot taken — find alternatives
      final alternatives = await _db.getAvailableSlots(
          doctor.id, date, 3);

      return BookingResult.slotTaken(alternatives);
    } catch (e) {
      _error = 'Booking failed: $e';
      return BookingResult.error(_error!);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cancelAppointment(
      String doctorId, String slotId) async {
    await _db.cancelAppointment(doctorId, slotId);
  }

  void clear() {
    _myAppointments = [];
    notifyListeners();
  }
}

/// Result of a booking attempt.
class BookingResult {
  final bool                       success;
  final AppointmentSlot?           appointment;
  final List<Map<String, dynamic>> alternatives; // [{date, timeSlot}]
  final String?                    errorMessage;

  const BookingResult._({
    required this.success,
    this.appointment,
    this.alternatives = const [],
    this.errorMessage,
  });

  factory BookingResult.success(AppointmentSlot a) =>
      BookingResult._(success: true, appointment: a);

  factory BookingResult.slotTaken(List<Map<String, dynamic>> alts) =>
      BookingResult._(success: false, alternatives: alts);

  factory BookingResult.error(String msg) =>
      BookingResult._(success: false, errorMessage: msg);

  bool get isSlotTaken => !success && errorMessage == null;
}