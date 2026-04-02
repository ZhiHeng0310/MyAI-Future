import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

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

    // ✅ FIX 1: initialize() takes a positional argument, not named 'settings:'
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:     DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }

    _initialized = true;
    debugPrint('NotificationService: ready');
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
      // ✅ FIX 2: the 4th and 5th arguments of zonedSchedule() are positional,
      // not named. Remove 'scheduledDate:' and 'notificationDetails:' labels.
      await _plugin.zonedSchedule(
        id,
        '💊 Medication Reminder',
        'Time to take $medicationName ($dosage)',
        scheduled,                                    // positional, no label
        NotificationDetails(android: _medChannel),    // positional, no label
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      try {
        // Fallback: inexact alarm (for devices that deny exact alarm permission)
        await _plugin.zonedSchedule(
          id,
          '💊 Medication Reminder',
          'Time to take $medicationName ($dosage)',
          scheduled,
          NotificationDetails(android: _medChannel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
      _stableId('remind_$medName'),
      '💊 Medication Reminder',
      'CareLoop AI: Please take your $medName ($dosage) now.',
      NotificationDetails(android: _medChannel),
    );
  }

  // ── Generic immediate ─────────────────────────────────────────────────────
  static Future<void> showImmediateReminder(String message) async {
    await init();
    await _plugin.show(
      0,
      '💊 CareLoop Reminder',
      message,
      NotificationDetails(android: _medChannel),
    );
  }

  // ── Health alert (high-risk AI) ───────────────────────────────────────────
  static Future<void> showHealthAlert(String message) async {
    await init();
    await _plugin.show(
      1,
      '🚨 CareLoop Health Alert',
      message,
      NotificationDetails(android: _alertChannel),
    );
  }

  // ── Queue / appointment status update ─────────────────────────────────────
  static Future<void> showQueueStatusNotification({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      2,
      title,
      body,
      NotificationDetails(android: _queueChannel),
    );
  }

  // ── Cancel helpers ────────────────────────────────────────────────────────
  static Future<void> cancelReminder(int id) => _plugin.cancel(id);

  static Future<void> cancelAllForMed(String medId, int slotCount) async {
    for (int i = 0; i < slotCount; i++) {
      await _plugin.cancel(medNotificationId(medId, i));
    }
  }

  // ── Stable integer IDs ────────────────────────────────────────────────────
  static int medNotificationId(String medId, int slotIndex) =>
      'med_${medId}_$slotIndex'.hashCode.abs() % 100000;

  static int _stableId(String key) => key.hashCode.abs() % 100000;
}