// lib/services/inbox_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
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

  // Start listening to notifications for a user
  void startListening(String userId) {
    if (_currentUserId == userId) return;
    _currentUserId = userId;

    print('🔔 InboxService: Starting listener for user $userId'); // ← ADD THIS

    _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      print('🔔 InboxService: Received ${snapshot.docs.length} notifications'); // ← ADD THIS

      _notifications = snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();

      _unreadCount = _notifications.where((n) => !n.isRead).length;

      print('🔔 InboxService: Unread count = $_unreadCount'); // ← ADD THIS
      notifyListeners();
    });
  }

  // Stop listening
  void stopListening() {
    _currentUserId = null;
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();
  }

  // Mark notification as read
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

  // Mark all as read
  Future<void> markAllAsRead() async {
    if (_currentUserId == null) return;

    try {
      final batch = _firestore.batch();
      final unreadDocs = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in unreadDocs.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  // Delete notification
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

  // Clear all notifications
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
  // CREATE NOTIFICATIONS (Called from various parts of the app)
  // ══════════════════════════════════════════════════════════════════════════

  /// Send appointment notification
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

  /// Send medication reminder (5 min late)
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
      message: 'You\'re 5 minutes late for $medicationName ($dosage). '
          'Please take it now!',
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

  /// Send queue update notification
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

    // Also trigger OS notification
    await NotificationService.showQueueStatusNotification(
      title: notification.title,
      body: message,
    );
  }

  /// Send doctor message notification
  static Future<void> sendDoctorMessage({
    required String userId,
    required String doctorName,
    required String message,
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

    // Also trigger OS notification
    await NotificationService.showHealthAlert(
      '👨‍⚕️ Dr. $doctorName: $message',
    );
  }

  /// Send general notification
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
  // HELPER METHODS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _saveAndNotify(NotificationModel notification) async {
    try {
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('notifications')
          .add(notification.toFirestore());

      debugPrint('✅ Notification saved: ${notification.title}');
    } catch (e) {
      debugPrint('❌ Error saving notification: $e');
    }
  }

  static String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');

    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }
}
