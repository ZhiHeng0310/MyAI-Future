// lib/services/medication_reminder_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'inbox_service.dart';
import 'notification_service.dart';

class MedicationReminderService {
  static final MedicationReminderService _instance =
  MedicationReminderService._();
  static MedicationReminderService get instance => _instance;
  MedicationReminderService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Timer> _activeTimers = {};
  String? _currentUserId;

  /// Start monitoring medications for a user
  void startMonitoring(String userId) {
    if (_currentUserId == userId) return; // Already monitoring

    stopMonitoring(); // Stop previous monitoring
    _currentUserId = userId;

    debugPrint('📊 Started medication monitoring for user: $userId');

    // Listen to medication schedule changes
    _firestore
        .collection('patient')
        .doc(userId)
        .collection('medications')
        .snapshots()
        .listen((snapshot) {
      _updateMedicationTimers(userId, snapshot.docs);
    });
  }

  /// Stop all monitoring
  void stopMonitoring() {
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _currentUserId = null;
    debugPrint('📊 Stopped medication monitoring');
  }

  /// Update timers based on medication data
  void _updateMedicationTimers(
      String userId,
      List<QueryDocumentSnapshot> medications,
      ) {
    // Cancel all existing timers
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();

    // Create new timers for each medication
    for (var doc in medications) {
      final data = doc.data() as Map<String, dynamic>;
      final medicationId = doc.id;
      final medicationName = data['name'] ?? 'Medication';
      final dosage = data['dosage'] ?? '';
      final times = data['times'] as List<dynamic>? ?? [];

      for (int i = 0; i < times.length; i++) {
        final timeStr = times[i] as String;
        _scheduleReminderCheck(
          userId: userId,
          medicationId: medicationId,
          medicationName: medicationName,
          dosage: dosage,
          timeStr: timeStr,
          slotIndex: i,
        );
      }
    }

    debugPrint('📊 Updated ${_activeTimers.length} medication timers');
  }

  /// Schedule a check 5 minutes after the scheduled time
  void _scheduleReminderCheck({
    required String userId,
    required String medicationId,
    required String medicationName,
    required String dosage,
    required String timeStr,
    required int slotIndex,
  }) {
    try {
      // Parse time (format: "HH:MM")
      final parts = timeStr.split(':');
      if (parts.length != 2) return;

      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return;

      // Calculate when to check (5 minutes after scheduled time)
      final now = DateTime.now();
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If time has passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Add 5 minutes delay
      final checkTime = scheduledTime.add(const Duration(minutes: 5));
      final delay = checkTime.difference(now);

      if (delay.isNegative) return; // Already passed

      // Create timer
      final timerKey = '${medicationId}_$slotIndex';
      _activeTimers[timerKey] = Timer(delay, () {
        _checkIfMedicationTaken(
          userId: userId,
          medicationId: medicationId,
          medicationName: medicationName,
          dosage: dosage,
          scheduledTime: scheduledTime,
          slotIndex: slotIndex,
        );
      });

      debugPrint('⏰ Scheduled reminder check for $medicationName at '
          '${checkTime.hour}:${checkTime.minute.toString().padLeft(2, "0")}');
    } catch (e) {
      debugPrint('❌ Error scheduling reminder: $e');
    }
  }

  /// Check if medication was taken, if not send reminder
  Future<void> _checkIfMedicationTaken({
    required String userId,
    required String medicationId,
    required String medicationName,
    required String dosage,
    required DateTime scheduledTime,
    required int slotIndex,
  }) async {
    try {
      debugPrint('🔍 Checking if $medicationName was taken...');

      // Check medication log
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final logs = await _firestore
          .collection('patient')
          .doc(userId)
          .collection('medication_logs')
          .where('medicationId', isEqualTo: medicationId)
          .where('scheduledTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('scheduledTime',
          isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // Check if medication was taken for this specific time slot
      bool wasTaken = false;
      for (var log in logs.docs) {
        final data = log.data();
        final logSlotIndex = data['slotIndex'] as int?;
        final taken = data['taken'] as bool? ?? false;

        if (logSlotIndex == slotIndex && taken) {
          wasTaken = true;
          break;
        }
      }

      if (!wasTaken) {
        debugPrint('💊 Medication NOT taken! Sending reminder...');

        // Send notification to inbox
        await InboxService.sendMedicationReminder(
          userId: userId,
          medicationName: medicationName,
          dosage: dosage,
          medicationId: medicationId,
        );

        // Also mark in database that reminder was sent
        await _firestore
            .collection('patient')
            .doc(userId)
            .collection('medication_logs')
            .add({
          'medicationId': medicationId,
          'medicationName': medicationName,
          'dosage': dosage,
          'scheduledTime': Timestamp.fromDate(scheduledTime),
          'slotIndex': slotIndex,
          'taken': false,
          'reminderSent': true,
          'reminderSentAt': FieldValue.serverTimestamp(),
        });
      } else {
        debugPrint('✅ Medication was taken on time');
      }

      // Schedule next check for tomorrow
      _scheduleReminderCheck(
        userId: userId,
        medicationId: medicationId,
        medicationName: medicationName,
        dosage: dosage,
        timeStr: '${scheduledTime.hour}:${scheduledTime.minute}',
        slotIndex: slotIndex,
      );
    } catch (e) {
      debugPrint('❌ Error checking medication: $e');
    }
  }

  /// Manually trigger a check (for testing)
  Future<void> triggerCheckNow({
    required String userId,
    required String medicationId,
    required String medicationName,
    required String dosage,
    required int slotIndex,
  }) async {
    await _checkIfMedicationTaken(
      userId: userId,
      medicationId: medicationId,
      medicationName: medicationName,
      dosage: dosage,
      scheduledTime: DateTime.now().subtract(const Duration(minutes: 6)),
      slotIndex: slotIndex,
    );
  }
}