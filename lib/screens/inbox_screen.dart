// lib/screens/inbox_screen.dart
// lib/screens/inbox_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';
import '../models/ai_summary_model.dart';
import '../providers/auth_provider.dart';
import '../screens/appointment/appointment_booking_screen.dart';
import '../screens/patient/patient_report_viewer_screen.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'home/home_screen.dart';
import '../services/inbox_service.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.teal,
        elevation: 0,
        actions: [
          // Refresh button
          Consumer<InboxService>(
            builder: (context, inbox, _) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh notifications',
                onPressed: () async {
                  await inbox.forceRefresh();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notifications refreshed'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              );
            },
          ),

          // Mark all as read
          Consumer<InboxService>(
            builder: (context, inbox, _) {
              if (inbox.hasUnread) {
                return IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Mark all as read',
                  onPressed: () => inbox.markAllAsRead(),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Clear all
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 8),
                    Text('Clear all'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'clear') {
                _showClearConfirmation(context);
              }
            },
          ),
        ],
      ),
      body: Consumer<InboxService>(
        builder: (context, inbox, _) {
          // Add debugging
          debugPrint('📱 InboxScreen: Rendering with ${inbox.notifications.length} notifications, ${inbox.unreadCount} unread');

          if (inbox.notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: inbox.notifications.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final notification = inbox.notifications[index];
              debugPrint('  📱 Rendering notification $index: ${notification.title}');
              return _NotificationTile(notification: notification);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications?'),
        content: const Text(
          'This will permanently delete all notifications. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<InboxService>().clearAll();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  Color _getAccentColor() {
    switch (notification.type) {
      case NotificationType.appointment:
        return Colors.blue;
      case NotificationType.medication:
        return Colors.orange;
      case NotificationType.queue:
        return Colors.purple;
      case NotificationType.doctor:
        return Colors.green;
      case NotificationType.general:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor();

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        context.read<InboxService>().deleteNotification(notification.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.white
              : accentColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.isRead
                ? Colors.grey.shade200
                : accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            if (!notification.isRead) {
              context.read<InboxService>().markAsRead(notification.id);
            }
            _handleNotificationTap(context);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon with unread indicator
                    Stack(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              notification.icon,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: notification.isRead
                                        ? FontWeight.w500
                                        : FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                notification.relativeTime,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification.message,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                          if (_isAppointmentRequest()) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _rejectAppointmentRequest(context),
                                    child: const Text('Reject'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _acceptAppointmentRequest(context),
                                    child: const Text('Accept & Book'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isAppointmentRequest() {
    return notification.type == NotificationType.appointment &&
        notification.metadata?['action'] == 'open_appointments' &&
        notification.metadata?['doctorId'] != null &&
        notification.metadata?['requestMessage'] != null;
  }

  Future<void> _acceptAppointmentRequest(BuildContext context) async {
    final doctorId = notification.metadata?['doctorId'] as String?;
    final doctorName = notification.metadata?['doctorName'] as String?;
    final requestMessage = notification.metadata?['requestMessage'] as String?;
    final patient = Provider.of<AuthProvider>(context, listen: false).patient;

    if (doctorId == null || patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open booking at this time.')),
      );
      return;
    }

    final doctor = await FirestoreService().getDoctor(doctorId);
    if (doctor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor information could not be loaded.')),
      );
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AppointmentBookingScreen(
        doctor: doctor,
        patient: patient,
        initialSymptoms: requestMessage != null && requestMessage.isNotEmpty
            ? [requestMessage]
            : [],
      ),
    ));
  }

  Future<void> _rejectAppointmentRequest(BuildContext context) async {
    final doctorId = notification.metadata?['doctorId'] as String?;
    final doctorName = notification.metadata?['doctorName'] as String?;
    final patient = Provider.of<AuthProvider>(context, listen: false).patient;

    if (doctorId == null || patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to send rejection.')),
      );
      return;
    }

    await InboxService.sendAppointmentUpdateNotification(
      userId: doctorId,
      title: '❌ Appointment Request Declined',
      message:
      '${patient.name} declined the appointment request from Dr. ${doctorName ?? 'your doctor'}.',
    );

    await NotificationService.sendPushToUser(
      userId:         doctorId,
      userCollection: 'doctors',
      title:          '❌ Appointment Request Declined',
      body:           '${patient.name} declined your appointment request.',
      channel:        'careloop_queue',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your rejection was sent to the doctor.')),
    );
  }

  void _handleNotificationTap(BuildContext context) {
    // Handle report summary notifications
    if (notification.type == NotificationType.general &&
        notification.metadata?['type'] == 'report_summary') {
      _handleReportSummaryNotification(context);
      return;
    }

    // Handle navigation based on notification type
    if (_isAppointmentRequest()) {
      _showAppointmentRequestDialog(context);
      return;
    }

    switch (notification.type) {
      case NotificationType.appointment:
      // Navigate to appointments
        if (notification.metadata?['appointmentId'] != null) {
          Navigator.pushNamed(
            context,
            '/appointment-details',
            arguments: notification.metadata!['appointmentId'],
          );
          return;
        }
        if (notification.metadata?['action'] == 'open_appointments') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 4)),
          );
        }
        break;
      case NotificationType.medication:
        if (notification.metadata?['action'] == 'open_medications') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 3)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 3)),
          );
        }
        break;
      case NotificationType.queue:
        if (notification.metadata?['action'] == 'open_appointments') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 4)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 1)),
          );
        }
        break;
      case NotificationType.doctor:
        if (notification.metadata?['action'] == 'open_appointments') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 4)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 2)),
          );
        }
        break;
      case NotificationType.general:
      // No specific action
        break;
    }
  }

  Future<void> _handleReportSummaryNotification(BuildContext context) async {
    final summaryId = notification.metadata?['summaryId'];

    if (summaryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report data not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch the summary from Firestore
      final summaryDoc = await FirebaseFirestore.instance
          .collection('report_summaries')
          .doc(summaryId)
          .get();

      if (!summaryDoc.exists || !context.mounted) {
        Navigator.pop(context); // Close loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final summaryData = summaryDoc.data()!['summaryData'];
      final summary = AISummary.fromJson(summaryData);

      // Close loading
      Navigator.pop(context);

      // Navigate to report viewer
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientReportViewerScreen(
              summary: summary,
              reportId: summaryDoc.data()!['reportId'],
            ),
          ),
        );
      }
    } catch (e) {
      // Close loading
      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAppointmentRequestDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Appointment Request'),
        content: Text(notification.message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectAppointmentRequest(context);
            },
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptAppointmentRequest(context);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}