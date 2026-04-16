import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// flutter_local_notifications is mobile/desktop only — guard with !kIsWeb
import 'notification_service_web_stub.dart'
  if (dart.library.io) 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Background message handler — top-level, mobile only
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return; // web handles via service worker
  final plugin = FlutterLocalNotificationsPlugin();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings     = DarwinInitializationSettings();
  const initSettings    = InitializationSettings(
      android: androidSettings, iOS: iosSettings);
  await plugin.initialize(settings: initSettings);

  final title     = message.notification?.title ?? message.data['title'] ?? 'CareLoop';
  final body      = message.notification?.body  ?? message.data['body']  ?? '';
  final channelId = message.data['channel'] ?? 'careloop_alerts';

  await plugin.show(
    id: message.hashCode,
    title: title,
    body:  body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId, _channelName(channelId),
         importance: Importance.max, priority: Priority.max,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}

String _channelName(String id) {
  switch (id) {
    case 'careloop_meds':  return 'Medication Reminders';
    case 'careloop_queue': return 'Queue Updates';
    default:               return 'Health Alerts';
  }
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Android channels ──────────────────────────────────────────────────────
  static const _medChannel = AndroidNotificationDetails(
    'careloop_meds', 'Medication Reminders',
    channelDescription: 'Reminders to take medication on time',
    importance: Importance.high, priority: Priority.high,
    icon: '@mipmap/ic_launcher', playSound: true,
  );

  static const _alertChannel = AndroidNotificationDetails(
    'careloop_alerts', 'Health Alerts',
    channelDescription: 'Urgent health notifications',
    importance: Importance.max, priority: Priority.max,
    icon: '@mipmap/ic_launcher', playSound: true,
  );

  static const _queueChannel = AndroidNotificationDetails(
    'careloop_queue', 'Queue Updates',
    channelDescription: 'Queue status updates from your clinic',
    importance: Importance.high, priority: Priority.high,
    icon: '@mipmap/ic_launcher', playSound: true,
  );

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;

    if (!kIsWeb) {
      // ── Local notifications (mobile/desktop only) ──────────────────────
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings     = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS:     iosSettings,
      );
      await _plugin.initialize(settings: initSettings);

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);
    }

    // ── FCM foreground listener (all platforms) ────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title   = message.notification?.title ?? message.data['title'] ?? 'CareLoop';
      final body    = message.notification?.body  ?? message.data['body']  ?? '';
      final channel = message.data['channel'] ?? 'careloop_alerts';
      _showFromData(title, body, channel);
    });

    // Request FCM permissions
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );

    _initialized = true;
    debugPrint('NotificationService: ready (web=$kIsWeb)');
  }

  // ── Show from FCM data ────────────────────────────────────────────────────
  static Future<void> _showFromData(
      String title, String body, String channelId) async {
    if (kIsWeb) {
      // On web, just log — browser notifications require user gesture
      debugPrint('Web notification: $title — $body');
      return;
    }
    AndroidNotificationDetails channel;
    switch (channelId) {
      case 'careloop_meds':  channel = _medChannel;   break;
      case 'careloop_queue': channel = _queueChannel; break;
      default:               channel = _alertChannel;
    }
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title, body: body,
      notificationDetails: NotificationDetails(android: channel),
    );
  }

  // ── Save FCM token to Firestore ───────────────────────────────────────────
  static Future<void> saveFcmToken(String userId, String collection) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection(collection).doc(userId)
          .set({'fcmToken': token});
      debugPrint('FCM token saved for $userId');

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection(collection).doc(userId)
            .set({'fcmToken': newToken});
      });
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  // ── FIX 5: Send push — stores to Firestore and shows local fallback ───────
  static Future<void> sendPushToUser({
    required String userId,
    required String userCollection,
    required String title,
    required String body,
    String channel = 'careloop_alerts',
  }) async {
    try {
      // Store to Firestore (visible to Cloud Functions in production)
      await FirebaseFirestore.instance.collection('push_notifications').add({
        'userId':     userId,
        'collection': userCollection,
        'title':      title,
        'body':       body,
        'channel':    channel,
        'sentAt':     FieldValue.serverTimestamp(),
        'status':     'pending',
      });

      // Show local notification as immediate fallback
      await _showFromData(title, body, channel);
    } catch (e) {
      debugPrint('sendPushToUser error: $e');
    }
  }

  // ── Schedule daily medication reminder ────────────────────────────────────
  /// FIX 5: Schedules OS-level reminder for medication at specified time.
  static Future<void> scheduleMedicationReminder({
    required int    id,
    required String medicationName,
    required String dosage,
    required String time,
  }) async {
    if (kIsWeb) return; // Scheduled notifications not supported on web
    await init();

    final parts  = time.split(':');
    final hour   = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: '💊 Medication Reminder',
        body:  'Time to take $medicationName ($dosage)',
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(android: _medChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Scheduled reminder for $medicationName at $time');
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: '💊 Medication Reminder',
          body:  'Time to take $medicationName ($dosage)',
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

  // ── FIX 5: Immediate missed-dose notification (fires at T+5 min) ──────────
  static Future<void> showMedicationReminder(
      String medName, String dosage) async {
    if (kIsWeb) {
      debugPrint('Web: Missed dose for $medName ($dosage)');
      return;
    }
    await init();
    await _plugin.show(
      id: 10000 + _stableId('remind_$medName'),
      title: '💊 Missed Medication',
      body:  'You\'re 5 minutes late for $medName ($dosage). Please take it now.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'careloop_meds', 'Medication Reminders',
          channelDescription: 'Reminders to take medication on time',
          importance: Importance.max, priority: Priority.max,
          icon: '@mipmap/ic_launcher', playSound: true,
          // Use a distinct sound/style for missed doses
          styleInformation: BigTextStyleInformation(
            'You\'re 5 minutes late for $medName ($dosage). '
                'Please take it now — consistent medication timing is important for your recovery.',
          ),
        ),
      ),
    );
  }

  static String _formatScheduledTime(String rawTime) {
    final parts = rawTime.split(':');
    if (parts.isEmpty) return rawTime;

    final hour = int.tryParse(parts[0]);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (hour == null) return rawTime;

    final formattedHour = hour.toString().padLeft(2, '0');
    final formattedMinute = (minute ?? 0).toString().padLeft(2, '0');
    return '$formattedHour:$formattedMinute';
  }

  static Future<void> showReminder(
      String medName, String dosage, String time) async {
    if (kIsWeb) {
      debugPrint('Web: Missed dose for $medName ($dosage) scheduled for $time');
      return;
    }
    await init();
    final scheduledTime = _formatScheduledTime(time);
    await _plugin.show(
      id: 10000 + _stableId('remind_${medName}_$scheduledTime'),
      title: '💊 Missed Medication',
      body:  'Please take $medName ($dosage) — scheduled for $scheduledTime',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'careloop_meds', 'Medication Reminders',
          channelDescription: 'Reminders to take medication on time',
          importance: Importance.max, priority: Priority.max,
          icon: '@mipmap/ic_launcher', playSound: true,
          // Use a distinct sound/style for missed doses
          styleInformation: BigTextStyleInformation(
            'Please take $medName ($dosage) — scheduled for $scheduledTime',
          ),
        ),
      ),
    );
  }

  // ── Generic immediate reminder ─────────────────────────────────────────────
  static Future<void> showImmediateReminder(String message) async {
    if (kIsWeb) { debugPrint('Web reminder: $message'); return; }
    await init();
    await _plugin.show(
      id: 20000,
      title: '💊 CareLoop Reminder',
      body:  message,
      notificationDetails: NotificationDetails(android: _medChannel),
    );
  }

  // ── Health alert ──────────────────────────────────────────────────────────
  static Future<void> showHealthAlert(String message) async {
    if (kIsWeb) { debugPrint('Web alert: $message'); return; }
    await init();
    await _plugin.show(
      id: 20001,
      title: '🚨 CareLoop Health Alert',
      body:  message,
      notificationDetails: NotificationDetails(android: _alertChannel),
    );
  }

  // ── Queue / appointment status update ─────────────────────────────────────
  static Future<void> showQueueStatusNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) { debugPrint('Web queue: $title — $body'); return; }
    await init();
    await _plugin.show(
      id: 20002,
      title: title,
      body:  body,
      notificationDetails: NotificationDetails(android: _queueChannel),
    );
  }

  // ── Cancel helpers ────────────────────────────────────────────────────────
  static Future<void> cancelReminder(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  // ── Stable IDs ────────────────────────────────────────────────────────────
  static int medNotificationId(String medId, int slotIndex) =>
      'med_${medId}_$slotIndex'.hashCode.abs() % 100000;

  static int _stableId(String key) => key.hashCode.abs() % 100000;
}