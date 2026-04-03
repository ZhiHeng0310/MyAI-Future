import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Show local notification when app is in background/terminated
  final plugin = FlutterLocalNotificationsPlugin();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initializationSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await plugin.initialize(settings: initializationSettings);

  final title = message.notification?.title ?? message.data['title'] ?? 'CareLoop';
  final body  = message.notification?.body  ?? message.data['body']  ?? '';
  final channelId = message.data['channel'] ?? 'careloop_alerts';

  await plugin.show(
    id: message.hashCode,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelName(channelId),
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}

String _channelName(String id) {
  switch (id) {
    case 'careloop_meds':   return 'Medication Reminders';
    case 'careloop_queue':  return 'Queue Updates';
    default:                return 'Health Alerts';
  }
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Channels ──────────────────────────────────────────────────────────────
  static const _medChannel = AndroidNotificationDetails(
    'careloop_meds', 'Medication Reminders',
    channelDescription: 'Reminders to take medication on time',
    importance: Importance.high,
    priority:   Priority.high,
    icon:       '@mipmap/ic_launcher',
    playSound:  true,
  );

  static const _alertChannel = AndroidNotificationDetails(
    'careloop_alerts', 'Health Alerts',
    channelDescription: 'Urgent health notifications',
    importance: Importance.max,
    priority:   Priority.max,
    icon:       '@mipmap/ic_launcher',
    playSound:  true,
  );

  static const _queueChannel = AndroidNotificationDetails(
    'careloop_queue', 'Queue Updates',
    channelDescription: 'Queue status updates from your clinic',
    importance: Importance.high,
    priority:   Priority.high,
    icon:       '@mipmap/ic_launcher',
    playSound:  true,
  );

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initializationSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }

    // ── FCM Setup ──────────────────────────────────────────────────────────
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handle foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? message.data['title'] ?? 'CareLoop';
      final body  = message.notification?.body  ?? message.data['body']  ?? '';
      final channel = message.data['channel'] ?? 'careloop_alerts';
      _showFromData(title, body, channel);
    });

    // Request FCM permissions
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
    debugPrint('NotificationService: ready');
  }

  static Future<void> _showFromData(String title, String body, String channelId) async {
    AndroidNotificationDetails channel;
    switch (channelId) {
      case 'careloop_meds':
        channel = _medChannel;
        break;
      case 'careloop_queue':
        channel = _queueChannel;
        break;
      default:
        channel = _alertChannel;
    }
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: channel),
    );
  }

  // ── Get & Store FCM Token ─────────────────────────────────────────────────
  /// Call this after user logs in to save their FCM token to Firestore.
  static Future<void> saveFcmToken(String userId, String collection) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(userId)
          .update({'fcmToken': token});
      debugPrint('FCM token saved for $userId');

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection(collection)
            .doc(userId)
            .update({'fcmToken': newToken});
      });
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  // ── Send FCM Push via Firestore trigger (or direct HTTP) ──────────────────
  /// Writes a push notification request to Firestore.
  /// In production, use Firebase Cloud Functions to send FCM.
  /// For demo: we store the notification and send local notification to simulate.
  static Future<void> sendPushToUser({
    required String userId,
    required String userCollection, // 'patients' or 'doctors'
    required String title,
    required String body,
    String channel = 'careloop_alerts',
  }) async {
    try {
      // Store notification in Firestore for record
      await FirebaseFirestore.instance.collection('push_notifications').add({
        'userId':     userId,
        'collection': userCollection,
        'title':      title,
        'body':       body,
        'channel':    channel,
        'sentAt':     FieldValue.serverTimestamp(),
        'status':     'pending',
      });

      // Also get FCM token and send directly (works when app is running)
      // For production, Firebase Cloud Functions should handle this
      final userDoc = await FirebaseFirestore.instance
          .collection(userCollection)
          .doc(userId)
          .get();

      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken != null) {
        debugPrint('FCM token found, notification queued for: $userId');
      }

      // Show local notification as fallback (visible when app is open)
      await _showFromData(title, body, channel);

    } catch (e) {
      debugPrint('sendPushToUser error: $e');
    }
  }

  // ── Schedule daily medication reminder ────────────────────────────────────
  static Future<void> scheduleMedicationReminder({
    required int    id,
    required String medicationName,
    required String dosage,
    required String time,
  }) async {
    await init();

    final parts  = time.split(':');
    final hour   = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final now       = tz.TZDateTime.now(tz.local);
    var   scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: '💊 Medication Reminder',
        body: 'Time to take $medicationName ($dosage)',
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(android: _medChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: '💊 Medication Reminder',
          body: 'Time to take $medicationName ($dosage)',
          scheduledDate: scheduled,
          notificationDetails: NotificationDetails(android: _medChannel),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        debugPrint('NotificationService: schedule failed $e');
      }
    }
  }

  // ── Immediate medication reminder ─────────────────────────────────────────
  static Future<void> showMedicationReminder(
      String medName, String dosage) async {
    await init();
    await _plugin.show(
      id: 10000 + _stableId('remind_$medName'),
      title: '💊 Medication Reminder',
      body: 'CareLoop AI: Please take your $medName ($dosage) now.',
      notificationDetails: NotificationDetails(android: _medChannel),
    );
  }

  // ── Generic immediate ─────────────────────────────────────────────────────
  static Future<void> showImmediateReminder(String message) async {
    await init();
    await _plugin.show(
      id: 20000,
      title: '💊 CareLoop Reminder',
      body: message,
      notificationDetails: NotificationDetails(android: _medChannel),
    );
  }

  // ── Health alert (high-risk AI) ───────────────────────────────────────────
  static Future<void> showHealthAlert(String message) async {
    await init();
    await _plugin.show(
      id: 20001,
      title: '🚨 CareLoop Health Alert',
      body: message,
      notificationDetails: NotificationDetails(android: _alertChannel),
    );
  }

  // ── Queue / appointment status update ─────────────────────────────────────
  static Future<void> showQueueStatusNotification({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: 20002,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: _queueChannel),
    );
  }

  // ── Cancel helpers ────────────────────────────────────────────────────────
  static Future<void> cancelReminder(int id) => _plugin.cancel(id: id);

  // ── Stable integer IDs ────────────────────────────────────────────────────
  static int medNotificationId(String medId, int slotIndex) =>
      'med_${medId}_$slotIndex'.hashCode.abs() % 100000;

  static int _stableId(String key) => key.hashCode.abs() % 100000;
}