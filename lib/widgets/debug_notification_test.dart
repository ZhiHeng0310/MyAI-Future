// lib/widgets/debug_notification_test.dart
// DEBUG WIDGET - Add this to patient home screen for testing
// Remove after debugging is complete

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/inbox_service.dart';

class DebugNotificationTest extends StatelessWidget {
  const DebugNotificationTest({Key? key}) : super(key: key);

  Future<void> _createTestNotification(BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No user logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debugPrint('🧪 TEST: Creating notification for userId: $userId');

    // Create test notification
    await InboxService.instance.createTestNotification(userId);

    // Query to verify
    await Future.delayed(const Duration(seconds: 1));
    await InboxService.instance.debugQueryNotifications(userId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Test notification created! Check console logs.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _queryNotifications(BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No user logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debugPrint('🔍 TEST: Querying notifications for userId: $userId');
    await InboxService.instance.debugQueryNotifications(userId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Query complete! Check console logs.'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                '🧪 DEBUG: Notification Testing',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Use these buttons to test if notifications are working:',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _createTestNotification(context),
                  icon: const Icon(Icons.add_alert, size: 18),
                  label: const Text('Create Test', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _queryNotifications(context),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Query All', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Check Flutter console (flutter run) for detailed logs',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}