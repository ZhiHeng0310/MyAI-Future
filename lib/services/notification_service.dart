import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ── Initialise ─────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    // Set local timezone — defaults to UTC if device zone not found
    try {
      final String timezoneName =
      DateTime.now().timeZoneName.isNotEmpty
          ? DateTime.now().timeZoneName
          : 'UTC';
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // ── Android notification channel ───────────────────────────────────────────
  static const _channel = AndroidNotificationDetails(
    'careloop_meds',
    'Medication Reminders',
    channelDescription: 'Daily reminders to take your medication',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  // ── Schedule a daily medication reminder ───────────────────────────────────
  static Future<void> scheduleMedicationReminder({
    required int id,
    required String medicationName,
    required String dosage,
    required String time,
  }) async {
    await init();

    final parts  = time.split(':');
    final hour   = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);

    // If today's slot already passed, push to tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      '💊 Medication Reminder',
      'Time to take $medicationName ($dosage)',
      scheduledDate,
      NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeats daily
    );
  }

  // ── Immediate reminder (triggered by AI action) ────────────────────────────
  static Future<void> showImmediateReminder(String message) async {
    await init();
    await _plugin.show(
      0,
      '💊 CareLoop Reminder',
      message,
      NotificationDetails(android: _channel),
    );
  }

  // ── Cancel a specific reminder ─────────────────────────────────────────────
  static Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
  }

  // ── Cancel all reminders for a medication ─────────────────────────────────
  static Future<void> cancelAllForMed(String medId, int timeSlotCount) async {
    for (int i = 0; i < timeSlotCount; i++) {
      await _plugin.cancel(medNotificationId(medId, i));
    }
  }

  // ── Stable integer ID from (medId, slot index) ────────────────────────────
  static int medNotificationId(String medId, int slotIndex) =>
      ('med_${medId}_$slotIndex').hashCode.abs() % 100000;
}  // ← this closing brace was missing in the original