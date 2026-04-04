// notification_service_web_stub.dart
// Web-compatible stub for flutter_local_notifications
// Synced with your notification_service.dart implementation

import 'dart:html' as html;
import 'package:flutter/foundation.dart' show debugPrint;

// ══════════════════════════════════════════════════════════════════════════════
// Main Plugin Class
// ══════════════════════════════════════════════════════════════════════════════

class FlutterLocalNotificationsPlugin {
  /// Initialize with named 'settings' parameter to match mobile API
  Future<void> initialize({
    required InitializationSettings settings,
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)? onDidReceiveBackgroundNotificationResponse,
  }) async {
    // Request browser notification permission
    if (html.Notification.supported) {
      final permission = await html.Notification.requestPermission();
      debugPrint('Web notification permission: $permission');
    } else {
      debugPrint('Web notifications not supported in this browser');
    }
  }

  /// Show notification with named 'id' parameter
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (html.Notification.supported && html.Notification.permission == 'granted') {
      try {
        final notification = html.Notification(
          title ?? 'CareLoop',
          body: body ?? '',
        );
        // Auto-close after 10 seconds
        Future.delayed(const Duration(seconds: 10), () {
          notification.close();
        });
        debugPrint('Web notification shown: $title');
      } catch (e) {
        debugPrint('Web notification error: $e');
      }
    } else if (html.Notification.permission == 'denied') {
      debugPrint('Web notifications are blocked. Enable them in browser settings.');
    } else {
      debugPrint('Web notification permission not granted');
    }
  }

  /// Schedule notification (web limitation: shows immediately)
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required dynamic scheduledDate, // TZDateTime on mobile
    required NotificationDetails notificationDetails,
    AndroidScheduleMode? androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
    dynamic uiLocalNotificationDateInterpretation,
    String? payload,
  }) async {
    // Web browsers don't support scheduled notifications reliably
    // Show immediately as fallback
    debugPrint('Web: Scheduled notification converted to immediate (scheduled for $scheduledDate)');
    await show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  /// Cancel notification with named 'id' parameter
  Future<void> cancel({required int id}) async {
    // Web notifications auto-close, no persistent cancel mechanism
    debugPrint('Web: Cancel notification #$id (auto-managed by browser)');
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    debugPrint('Web: Cancel all notifications (auto-managed by browser)');
  }

  /// Resolve platform-specific implementation
  T? resolvePlatformSpecificImplementation<T>() {
    if (T == AndroidFlutterLocalNotificationsPlugin) {
      return AndroidFlutterLocalNotificationsPlugin() as T;
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Initialization Settings
// ══════════════════════════════════════════════════════════════════════════════

class InitializationSettings {
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;
  final LinuxInitializationSettings? linux;
  final MacOSInitializationSettings? macOS;

  const InitializationSettings({
    this.android,
    this.iOS,
    this.linux,
    this.macOS,
  });
}

class AndroidInitializationSettings {
  final String defaultIcon;

  const AndroidInitializationSettings(this.defaultIcon);
}

class DarwinInitializationSettings {
  final bool? requestAlertPermission;
  final bool? requestBadgePermission;
  final bool? requestSoundPermission;
  final bool? defaultPresentAlert;
  final bool? defaultPresentSound;
  final bool? defaultPresentBadge;

  const DarwinInitializationSettings({
    this.requestAlertPermission,
    this.requestBadgePermission,
    this.requestSoundPermission,
    this.defaultPresentAlert,
    this.defaultPresentSound,
    this.defaultPresentBadge,
  });
}

class LinuxInitializationSettings {
  const LinuxInitializationSettings({String? defaultActionName});
}

class MacOSInitializationSettings {
  const MacOSInitializationSettings();
}

// ══════════════════════════════════════════════════════════════════════════════
// Notification Details
// ══════════════════════════════════════════════════════════════════════════════

class NotificationDetails {
  final AndroidNotificationDetails? android;
  final DarwinNotificationDetails? iOS;
  final LinuxNotificationDetails? linux;
  final MacOSNotificationDetails? macOS;

  const NotificationDetails({
    this.android,
    this.iOS,
    this.linux,
    this.macOS,
  });
}

class AndroidNotificationDetails {
  final String channelId;
  final String channelName;
  final String? channelDescription;
  final Importance? importance;
  final Priority? priority;
  final String? icon;
  final bool? playSound;
  final String? sound;
  final bool? enableVibration;
  final List<int>? vibrationPattern;
  final StyleInformation? styleInformation;
  final String? groupKey;
  final bool? setAsGroupSummary;
  final GroupAlertBehavior? groupAlertBehavior;
  final bool? autoCancel;
  final bool? ongoing;
  final dynamic color;
  final dynamic largeIcon;
  final bool? onlyAlertOnce;
  final bool? showWhen;
  final int? when;
  final bool? usesChronometer;
  final bool? channelShowBadge;
  final bool? showProgress;
  final int? maxProgress;
  final int? progress;
  final bool? indeterminate;

  const AndroidNotificationDetails(
      this.channelId,
      this.channelName, {
        this.channelDescription,
        this.importance,
        this.priority,
        this.icon,
        this.playSound,
        this.sound,
        this.enableVibration,
        this.vibrationPattern,
        this.styleInformation,
        this.groupKey,
        this.setAsGroupSummary,
        this.groupAlertBehavior,
        this.autoCancel,
        this.ongoing,
        this.color,
        this.largeIcon,
        this.onlyAlertOnce,
        this.showWhen,
        this.when,
        this.usesChronometer,
        this.channelShowBadge,
        this.showProgress,
        this.maxProgress,
        this.progress,
        this.indeterminate,
      });
}

class DarwinNotificationDetails {
  final String? sound;
  final bool? presentAlert;
  final bool? presentBadge;
  final bool? presentSound;
  final String? subtitle;
  final int? badgeNumber;

  const DarwinNotificationDetails({
    this.sound,
    this.presentAlert,
    this.presentBadge,
    this.presentSound,
    this.subtitle,
    this.badgeNumber,
  });
}

class LinuxNotificationDetails {
  const LinuxNotificationDetails();
}

class MacOSNotificationDetails {
  const MacOSNotificationDetails();
}

// ══════════════════════════════════════════════════════════════════════════════
// Style Information
// ══════════════════════════════════════════════════════════════════════════════

abstract class StyleInformation {
  const StyleInformation();
}

class BigTextStyleInformation extends StyleInformation {
  final String bigText;
  final bool? htmlFormatBigText;
  final String? contentTitle;
  final bool? htmlFormatContentTitle;
  final String? summaryText;
  final bool? htmlFormatSummaryText;

  const BigTextStyleInformation(
      this.bigText, {
        this.htmlFormatBigText,
        this.contentTitle,
        this.htmlFormatContentTitle,
        this.summaryText,
        this.htmlFormatSummaryText,
      });
}

class BigPictureStyleInformation extends StyleInformation {
  const BigPictureStyleInformation(dynamic largeIcon);
}

class InboxStyleInformation extends StyleInformation {
  const InboxStyleInformation(List<String> lines);
}

class MessagingStyleInformation extends StyleInformation {
  const MessagingStyleInformation(dynamic person);
}

// ══════════════════════════════════════════════════════════════════════════════
// Enums
// ══════════════════════════════════════════════════════════════════════════════

class Importance {
  static const unspecified = Importance._();
  static const min = Importance._();
  static const low = Importance._();
  static const defaultImportance = Importance._();
  static const high = Importance._();
  static const max = Importance._();
  const Importance._();
}

class Priority {
  static const min = Priority._();
  static const low = Priority._();
  static const defaultPriority = Priority._();
  static const high = Priority._();
  static const max = Priority._();
  const Priority._();
}

class GroupAlertBehavior {
  static const all = GroupAlertBehavior._();
  static const summary = GroupAlertBehavior._();
  static const children = GroupAlertBehavior._();
  const GroupAlertBehavior._();
}

class AndroidScheduleMode {
  static const exact = AndroidScheduleMode._();
  static const exactAllowWhileIdle = AndroidScheduleMode._();
  static const inexact = AndroidScheduleMode._();
  static const inexactAllowWhileIdle = AndroidScheduleMode._();
  const AndroidScheduleMode._();
}

class DateTimeComponents {
  static const time = DateTimeComponents._();
  static const dayOfWeekAndTime = DateTimeComponents._();
  static const dayOfMonthAndTime = DateTimeComponents._();
  static const dateAndTime = DateTimeComponents._();
  const DateTimeComponents._();
}

// ══════════════════════════════════════════════════════════════════════════════
// Android-Specific Plugin
// ══════════════════════════════════════════════════════════════════════════════

class AndroidFlutterLocalNotificationsPlugin {
  /// Request notification permission (web auto-handles this)
  Future<bool?> requestNotificationsPermission() async {
    if (html.Notification.supported) {
      final permission = await html.Notification.requestPermission();
      debugPrint('Web: Notification permission = $permission');
      return permission == 'granted';
    }
    return false;
  }

  /// Request exact alarms permission (not applicable on web)
  Future<bool?> requestExactAlarmsPermission() async {
    debugPrint('Web: Exact alarms not applicable (browser limitation)');
    return true; // Return true to avoid blocking initialization
  }

  Future<bool?> canScheduleExactNotifications() async => false;

  Future<List<ActiveNotification>> getActiveNotifications() async => [];
}

class ActiveNotification {
  final int id;
  final String? title;
  final String? body;

  const ActiveNotification(this.id, this.title, this.body);
}

// ══════════════════════════════════════════════════════════════════════════════
// Notification Response
// ══════════════════════════════════════════════════════════════════════════════

class NotificationResponse {
  final int? id;
  final String? actionId;
  final String? input;
  final String? payload;
  final NotificationResponseType notificationResponseType;

  const NotificationResponse({
    this.id,
    this.actionId,
    this.input,
    this.payload,
    required this.notificationResponseType,
  });
}

enum NotificationResponseType {
  selectedNotification,
  selectedNotificationAction,
}

// ══════════════════════════════════════════════════════════════════════════════
// Additional Types (for completeness)
// ══════════════════════════════════════════════════════════════════════════════

class RepeatInterval {
  static const everyMinute = RepeatInterval._();
  static const hourly = RepeatInterval._();
  static const daily = RepeatInterval._();
  static const weekly = RepeatInterval._();
  const RepeatInterval._();
}

class Day {
  static const monday = Day._();
  static const tuesday = Day._();
  static const wednesday = Day._();
  static const thursday = Day._();
  static const friday = Day._();
  static const saturday = Day._();
  static const sunday = Day._();
  const Day._();
}