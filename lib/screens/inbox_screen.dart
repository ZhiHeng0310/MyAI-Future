// lib/screens/inbox_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_model.dart';
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
          if (inbox.notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: inbox.notifications.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final notification = inbox.notifications[index];
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
            child: Row(
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleNotificationTap(BuildContext context) {
    // Handle navigation based on notification type
    switch (notification.type) {
      case NotificationType.appointment:
      // Navigate to appointments
        if (notification.metadata?['appointmentId'] != null) {
          Navigator.pushNamed(
            context,
            '/appointment-details',
            arguments: notification.metadata!['appointmentId'],
          );
        }
        break;
      case NotificationType.medication:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 3)),
        );
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
}
