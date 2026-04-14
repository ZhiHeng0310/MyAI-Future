import 'package:flutter/material.dart';
import '../models/appointment_model.dart';
import '../models/patient_model.dart';
import '../models/doctor_model.dart';
import '../models/health_alert_model.dart' hide DoctorInboxMessage; // ✅ FIX 3: Added for DoctorInboxMessage
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/inbox_service.dart';

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
        // ✅ FIX 3: Success — send MULTIPLE types of notifications

        // 1. Local OS notification (immediate)
        await NotificationService.showQueueStatusNotification(
          title: '✅ Appointment confirmed',
          body:  'Your appointment with Dr. ${doctor.name} '
              'on ${appt.dateLabel} at $timeSlot is confirmed.',
        );

        debugPrint('✅ Sent local notification for appointment');

        // 2. Notification inbox entry (persistent in app)
        await InboxService.sendAppointmentNotification(
          userId:          patient.id,
          doctorName:      doctor.name,
          appointmentTime: appt.date,
          appointmentId:   appt.id,
        );

        debugPrint('✅ Sent inbox notification for appointment');

        // 3. Notify the doctor that the patient booked the request
        await InboxService.sendAppointmentUpdateNotification(
          userId: doctor.id,
          title: '✅ Appointment booked by ${patient.name}',
          message: '${patient.name} confirmed the appointment request for '
              '${appt.dateLabel} at ${appt.timeSlot}.',
        );

        debugPrint('✅ Sent doctor notification for booked appointment');

        // ✅ FIX 3: Also add to doctor_inbox collection so it appears in doctor's inbox tab
        await _db.createDoctorInboxMessage(
          DoctorInboxMessage(
            id: '',
            doctorId: doctor.id,
            patientId: patient.id,
            patientName: patient.name,
            message: '📅 ${patient.name} booked an appointment for ${appt.dateLabel} at ${appt.timeSlot}.',
            type: 'appointment_booked',
            read: false,
            createdAt: DateTime.now(),
          ),
        );

        debugPrint('✅ FIX 3: Added appointment notification to doctor inbox');

        // 4. Notify the doctor via push as well when the patient confirms
        await NotificationService.sendPushToUser(
          userId:         doctor.id,
          userCollection: 'doctors',
          title:          '✅ Appointment Confirmed',
          body:           '${patient.name} confirmed the appointment request for ${appt.dateLabel} at ${appt.timeSlot}.',
          channel:        'careloop_queue',
        );

        debugPrint('✅ Sent push notification to doctor for booked appointment');

        // 5. Send a medication review prompt to the patient
        await InboxService.sendMedicationReviewNotification(
          userId: patient.id,
          doctorName: doctor.name,
        );

        debugPrint('✅ Sent medication review notification');

        // 5. Push notification (works when app is closed/background)
        await NotificationService.sendPushToUser(
          userId:         patient.id,
          userCollection: 'patients',
          title:          '✅ Appointment Confirmed',
          body:           'Dr. ${doctor.name} on ${appt.dateLabel} at $timeSlot',
          channel:        'careloop_queue',
        );

        debugPrint('✅ Sent push notification for appointment');

        return BookingResult.success(appt);
      }

      // Slot taken — find alternatives
      final alternatives = await _db.getAvailableSlots(
          doctor.id, date, 3);

      return BookingResult.slotTaken(alternatives);
    } catch (e) {
      debugPrint('❌ Booking error: $e');
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