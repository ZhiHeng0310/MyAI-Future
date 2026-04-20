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
          try {
            debugPrint('📱 InboxScreen: Rendering ${inbox.notifications.length} notifications');

            if (inbox.notifications.isEmpty) {
              return Column(
                children: [
                  _buildEmptyState(),
                  // Add refresh button in empty state
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await inbox.forceRefresh();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Refreshed from server'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Notifications'),
                    ),
                  ),
                ],
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await inbox.forceRefresh();
              },
              child: ListView.builder(
                itemCount: inbox.notifications.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  try {
                    final notification = inbox.notifications[index];
                    return _NotificationTile(notification: notification);
                  } catch (e) {
                    debugPrint('❌ Error rendering notification $index: $e');
                    return const SizedBox.shrink(); // Skip broken notifications
                  }
                },
              ),
            );
          } catch (e, stackTrace) {
            debugPrint('❌ Critical error in InboxScreen: $e');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Error loading notifications'),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => inbox.forceRefresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry from Server'),
                  ),
                ],
              ),
            );
          }
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
    // Defensive: Ensure notification has valid data
    if (notification.title.isEmpty && notification.message.isEmpty) {
      debugPrint('⚠️ Skipping empty notification ${notification.id}');
      return const SizedBox.shrink();
    }

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
                                  notification.title.isNotEmpty
                                      ? notification.title
                                      : 'Notification',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: notification.isRead
                                        ? FontWeight.w500
                                        : FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                            notification.message.isNotEmpty
                                ? notification.message
                                : 'No message',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_isAppointmentRequest()) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                    ),
                                    onPressed: () => _rejectAppointmentRequest(context),
                                    child: const Text('Decline'),
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
    try {
      return notification.type == NotificationType.appointment &&
          notification.metadata != null &&
          notification.metadata!['action'] == 'open_appointments' &&
          notification.metadata!['doctorId'] != null &&
          notification.metadata!['requestMessage'] != null &&
          notification.metadata!['responded'] != true; // hide buttons after responding
    } catch (e) {
      debugPrint('⚠️ Error checking appointment request: $e');
      return false;
    }
  }

  Future<void> _acceptAppointmentRequest(BuildContext context) async {
    try {
      final doctorId = notification.metadata?['doctorId'] as String?;
      final doctorName = notification.metadata?['doctorName'] as String?;
      final requestMessage = notification.metadata?['requestMessage'] as String?;
      final requestId = notification.metadata?['requestId'] as String?;
      final patient = Provider.of<AuthProvider>(context, listen: false).patient;

      if (doctorId == null || patient == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to open booking at this time.')),
          );
        }
        return;
      }

      // 1. Mark the notification as responded so buttons disappear.
      if (notification.id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(notification.id)
            .update({'metadata.responded': true, 'isRead': true});
      }

      // 2. Update the appointment_requests doc status (if we have the ID).
      if (requestId != null && requestId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('appointment_requests')
            .doc(requestId)
            .update({'status': 'accepted'});
      }

      // 3. Notify the doctor that the patient accepted.
      await InboxService.sendAppointmentUpdateNotification(
        userId: doctorId,
        title: '✅ Appointment Request Accepted',
        message:
        '${patient.name} accepted your appointment request and is now booking a time.',
        metadata: {
          'patientId': patient.id,
          'patientName': patient.name,
          'action': 'patient_accepted',
        },
      );

      // 4. Load doctor model and navigate to booking screen.
      if (!context.mounted) return;

      final doctor = await FirestoreService().getDoctor(doctorId);
      if (doctor == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Doctor information could not be loaded.')),
          );
        }
        return;
      }

      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AppointmentBookingScreen(
          doctor: doctor,
          patient: patient,
          initialSymptoms: (requestMessage != null && requestMessage.isNotEmpty)
              ? [requestMessage]
              : [],
        ),
      ));
    } catch (e) {
      debugPrint('❌ Error accepting appointment request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _rejectAppointmentRequest(BuildContext context) async {
    try {
      final doctorId = notification.metadata?['doctorId'] as String?;
      final doctorName = notification.metadata?['doctorName'] as String?;
      final requestId = notification.metadata?['requestId'] as String?;
      final patient = Provider.of<AuthProvider>(context, listen: false).patient;

      if (doctorId == null || patient == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to send rejection.')),
          );
        }
        return;
      }

      // 1. Mark the notification as responded so buttons disappear.
      if (notification.id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(notification.id)
            .update({'metadata.responded': true, 'isRead': true});
      }

      // 2. Update the appointment_requests doc status (if we have the ID).
      if (requestId != null && requestId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('appointment_requests')
            .doc(requestId)
            .update({'status': 'declined'});
      }

      // 3. Send a notification to the doctor.
      await InboxService.sendAppointmentUpdateNotification(
        userId: doctorId,
        title: '❌ Appointment Request Declined',
        message:
        '${patient.name} declined your appointment request.',
        metadata: {
          'patientId': patient.id,
          'patientName': patient.name,
          'action': 'patient_declined',
        },
      );

      // 4. Push notification so the doctor sees it immediately.
      await NotificationService.sendPushToUser(
        userId: doctorId,
        userCollection: 'doctors',
        title: '❌ Appointment Request Declined',
        body: '${patient.name} declined your appointment request.',
        channel: 'careloop_queue',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rejection sent. The doctor has been notified.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error rejecting appointment request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _handleNotificationTap(BuildContext context) {
    try {
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
    } catch (e) {
      debugPrint('❌ Error handling notification tap: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open notification')),
      );
    }
  }

  Future<void> _handleReportSummaryNotification(BuildContext context) async {
    try {
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
      debugPrint('❌ Error loading report: $e');
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _rejectAppointmentRequest(context);
            },
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptAppointmentRequest(context);
            },
            child: const Text('Accept & Book'),
          ),
        ],
      ),
    );
  }
}