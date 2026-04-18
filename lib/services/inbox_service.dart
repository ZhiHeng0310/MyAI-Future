// lib/services/inbox_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

class InboxService extends ChangeNotifier {
  static final InboxService _instance = InboxService._();
  static InboxService get instance => _instance;
  InboxService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  String? _currentUserId;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  // ── Start listening ───────────────────────────────────────────────────────

  void startListening(String userId) {
    if (_currentUserId == userId) {
      debugPrint('🔔 InboxService: Already listening for user $userId');
      return;
    }
    _currentUserId = userId;

    debugPrint('🔔 InboxService: Starting listener for user $userId');
    debugPrint('🔔 InboxService: Query: notifications.where(userId == $userId).orderBy(timestamp desc)');

    _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) {
        try {
          debugPrint('🔔 InboxService: Received ${snapshot.docs.length} notifications');

          // Debug: Print raw document data
          if (snapshot.docs.isNotEmpty) {
            debugPrint('🔔 InboxService: Sample notification data:');
            final firstDoc = snapshot.docs.first;
            debugPrint('   ID: ${firstDoc.id}');
            debugPrint('   Data: ${firstDoc.data()}');
          }

          _notifications = snapshot.docs
              .map((doc) {
            try {
              final notification = NotificationModel.fromFirestore(doc);
              debugPrint('   ✅ Parsed: ${notification.title} (${notification.type})');
              return notification;
            } catch (e) {
              debugPrint('   ❌ Error parsing notification ${doc.id}: $e');
              debugPrint('   ❌ Data: ${doc.data()}');
              return null;
            }
          })
              .where((n) => n != null)
              .cast<NotificationModel>()
              .toList();

          _unreadCount = _notifications.where((n) => !n.isRead).length;

          debugPrint('🔔 InboxService: Parsed ${_notifications.length} notifications, Unread count = $_unreadCount');

          notifyListeners();
          debugPrint('🔔 InboxService: notifyListeners() called');
        } catch (e) {
          debugPrint('❌ InboxService: Error processing notifications: $e');
          debugPrint('❌ Stack trace: ${StackTrace.current}');
        }
      },
      onError: (error) {
        debugPrint('❌ InboxService: Stream error: $error');
        if (error is FirebaseException) {
          debugPrint('❌ Firebase error code: ${error.code}');
          debugPrint('❌ Firebase error message: ${error.message}');
        }
      },
    );
  }

  void stopListening() {
    _currentUserId = null;
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();
  }

  // Force refresh notifications from Firestore
  Future<void> forceRefresh() async {
    if (_currentUserId == null) {
      debugPrint('⚠️ InboxService: Cannot refresh - no user ID set');
      return;
    }

    try {
      debugPrint('🔄 InboxService: Force refreshing notifications for $_currentUserId');
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      _notifications = snapshot.docs
          .map((doc) {
        try {
          return NotificationModel.fromFirestore(doc);
        } catch (e) {
          debugPrint('⚠️ Error parsing notification ${doc.id}: $e');
          return null;
        }
      })
          .where((n) => n != null)
          .cast<NotificationModel>()
          .toList();

      _unreadCount = _notifications.where((n) => !n.isRead).length;

      debugPrint('✅ InboxService: Force refresh complete - ${_notifications.length} notifications, $_unreadCount unread');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ InboxService: Force refresh error: $e');
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Notification marked as read: $notificationId');
    } catch (e) {
      debugPrint('⚠️ Error marking notification as read: $e');
      // Try alternative approach if BloomFilter error
      if (e.toString().contains('BloomFilter')) {
        try {
          // Force a fresh read then update
          final doc = await FirebaseFirestore.instance
              .collection('notifications')
              .doc(notificationId)
              .get(const GetOptions(source: Source.server)); // Force server read

          if (doc.exists) {
            await doc.reference.update({
              'isRead': true,
              'readAt': FieldValue.serverTimestamp(),
            });
            debugPrint('✅ Notification marked as read (retry): $notificationId');
          }
        } catch (retryError) {
          debugPrint('❌ Failed to mark notification as read even on retry: $retryError');
        }
      }
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    if (_currentUserId == null) return;
    try {
      // Get all notifications (no isRead filter = no composite index needed)
      final allDocs = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUserId)
          .get();

      // Filter unread locally
      final unreadDocs = allDocs.docs.where((doc) {
        final data = doc.data();
        return data['isRead'] != true;
      }).toList();

      // Batch update all unread notifications
      if (unreadDocs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in unreadDocs) {
          batch.update(doc.reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        debugPrint('✅ Marked ${unreadDocs.length} notifications as read');
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }

  Future<void> clearAll() async {
    if (_currentUserId == null) return;
    try {
      final batch = _firestore.batch();
      final docs = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUserId)
          .get();
      for (var doc in docs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREATE NOTIFICATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Appointment confirmed — navigates to appointment details
  static Future<void> sendAppointmentNotification({
    required String userId,
    required String doctorName,
    required DateTime appointmentTime,
    String? appointmentId,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '📅 Appointment Confirmed',
      message: 'Your appointment with Dr. $doctorName is scheduled for '
          '${_formatDateTime(appointmentTime)}',
      type: NotificationType.appointment,
      timestamp: DateTime.now(),
      metadata: {
        'appointmentId': appointmentId,
        'doctorName': doctorName,
        'appointmentTime': appointmentTime.toIso8601String(),
      },
    );
    await _saveAndNotify(notification);
  }

  /// Appointment REQUEST from doctor — includes action to open calendar
  static Future<void> sendAppointmentRequestNotification({
    required String userId,
    required String doctorId,
    required String doctorName,
    required String message,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '📅 Appointment Request from Dr. $doctorName',
      message: '$message\n\nTap to respond and choose a time.',
      type: NotificationType.appointment,
      timestamp: DateTime.now(),
      metadata: {
        'doctorId': doctorId,
        'doctorName': doctorName,
        'requestMessage': message,
        'action': 'open_appointments', // triggers appointment request handling in InboxScreen
      },
    );
    await _saveAndNotify(notification);
  }

  /// Send a general appointment update to a user.
  static Future<void> sendAppointmentUpdateNotification({
    required String userId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: title,
      message: message,
      type: NotificationType.appointment,
      timestamp: DateTime.now(),
      metadata: {
        'action': 'open_appointments',
        ...?metadata,
      },
    );
    await _saveAndNotify(notification);
  }

  /// Medication review notification that opens the medications tab.
  static Future<void> sendMedicationReviewNotification({
    required String userId,
    required String doctorName,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '💊 Review your medications before your visit',
      message:
      'Your appointment with Dr. $doctorName is coming up. Please review your medications before the visit.',
      type: NotificationType.medication,
      timestamp: DateTime.now(),
      metadata: {'action': 'open_medications'},
    );
    await _saveAndNotify(notification);
  }

  /// Medication reminder (5 min late) — navigates to meds screen
  static Future<void> sendMedicationReminder({
    required String userId,
    required String medicationName,
    required String dosage,
    String? medicationId,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '💊 Missed Medication',
      message:
      'You\'re 5 minutes late for $medicationName ($dosage). Please take it now!',
      type: NotificationType.medication,
      timestamp: DateTime.now(),
      metadata: {
        'medicationId': medicationId,
        'medicationName': medicationName,
        'dosage': dosage,
      },
    );
    await _saveAndNotify(notification);

    // Also trigger OS notification
    await NotificationService.showMedicationReminder(medicationName, dosage);
  }

  static Future<void> sendReminder({
    required String userId,
    required String medicationName,
    required String dosage,
    String? scheduledTime,
    String? medicationId,
  }) async {
    final scheduledLabel = scheduledTime ?? dosage;

    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '💊 Medication Reminder',
      message:
      'Please take $medicationName ($dosage) — scheduled for $scheduledLabel',
      type: NotificationType.medication,
      timestamp: DateTime.now(),
      metadata: {
        'action': 'open_medications',
        'medicationId': medicationId,
        'medicationName': medicationName,
        'dosage': dosage,
        'scheduledTime': scheduledTime,
      },
    );
    await _saveAndNotify(notification);

    // Also trigger OS notification
    await NotificationService.showReminder(medicationName, dosage, scheduledLabel);
  }

  /// Queue update — navigates to queue or appointments screen
  static Future<void> sendQueueNotification({
    required String userId,
    required String message,
    bool isUrgent = false,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: isUrgent ? '🚨 Urgent Queue Update' : '🏥 Queue Update',
      message: message,
      type: NotificationType.queue,
      timestamp: DateTime.now(),
      metadata: {'isUrgent': isUrgent},
    );
    await _saveAndNotify(notification);

    await NotificationService.showQueueStatusNotification(
      title: notification.title,
      body: message,
    );
  }

  /// Doctor message / response — navigates to AI chat or appointments
  static Future<void> sendDoctorMessage({
    required String userId,
    required String doctorName,
    required String message,
    String? doctorId,
    Map<String, dynamic>? metadata,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: '👨‍⚕️ Message from Dr. $doctorName',
      message: message,
      type: NotificationType.doctor,
      timestamp: DateTime.now(),
      metadata: {
        'doctorName': doctorName,
        ...?metadata,
      },
    );

    await _saveAndNotify(notification);

    if (doctorId != null) {
      try {
        await FirestoreService().createPatientInboxMessage(
          patientId: userId,
          message: '📩 Message from Dr. $doctorName: $message',
          type: 'doctor_message',
          doctorId: doctorId,
        );
      } catch (e) {
        debugPrint('⚠️ Failed to mirror doctor message to patient inbox: $e');
      }
    }

    await NotificationService.showHealthAlert(
      '👨‍⚕️ Dr. $doctorName: $message',
    );
  }

  /// General notification
  static Future<void> sendGeneralNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: title,
      message: message,
      type: NotificationType.general,
      timestamp: DateTime.now(),
    );
    await _saveAndNotify(notification);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _saveAndNotify(NotificationModel notification) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .add(notification.toFirestore());
      debugPrint('✅ Notification saved: ${notification.title}');
    } catch (e) {
      debugPrint('❌ Error saving notification: $e');
    }
  }

  static String _formatDateTime(DateTime dt) {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final hour =
    dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DEBUG/TEST FUNCTIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Create a test notification to verify the system is working
  Future<void> createTestNotification(String userId) async {
    try {
      debugPrint('🧪 Creating test notification for user: $userId');

      final testNotification = {
        'userId': userId,
        'title': '🧪 Test Notification',
        'message': 'This is a test notification to verify the system is working',
        'type': 'general',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': {
          'type': 'test',
          'testId': 'test_${DateTime.now().millisecondsSinceEpoch}',
        }
      };

      final docRef = await _firestore
          .collection('notifications')
          .add(testNotification);

      debugPrint('✅ Test notification created with ID: ${docRef.id}');
      debugPrint('   UserId: $userId');
      debugPrint('   Data: $testNotification');

    } catch (e) {
      debugPrint('❌ Error creating test notification: $e');
      if (e is FirebaseException) {
        debugPrint('   Code: ${e.code}');
        debugPrint('   Message: ${e.message}');
      }
    }
  }

  /// Query notifications directly to verify they exist
  Future<void> debugQueryNotifications(String userId) async {
    try {
      debugPrint('🔍 Debug: Querying notifications for user: $userId');

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      debugPrint('🔍 Debug: Found ${snapshot.docs.length} notifications');

      for (var doc in snapshot.docs) {
        debugPrint('   📋 ${doc.id}:');
        debugPrint('      ${doc.data()}');
      }

    } catch (e) {
      debugPrint('❌ Error querying notifications: $e');
      if (e is FirebaseException) {
        debugPrint('   Code: ${e.code}');
        debugPrint('   Message: ${e.message}');
      }
    }
  }
}