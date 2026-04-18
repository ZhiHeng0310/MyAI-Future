// lib/models/notification_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

enum NotificationType {
  appointment,      // Appointment booked successfully
  medication,       // Medication reminder (5 min late)
  queue,           // Queue status (urgent/next)
  doctor,          // Message from doctor
  general,         // General notifications
}

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata; // Extra data (appointment ID, med ID, etc)

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
  });

  // Convert from Firestore
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse timestamp - handle both Firestore Timestamp and ISO string
    DateTime parsedTimestamp;
    final timestampData = data['timestamp'];

    if (timestampData is Timestamp) {
      // Firestore Timestamp object
      parsedTimestamp = timestampData.toDate();
    } else if (timestampData is String) {
      // ISO 8601 string
      try {
        parsedTimestamp = DateTime.parse(timestampData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse timestamp string: $timestampData');
        parsedTimestamp = DateTime.now();
      }
    } else {
      // Fallback to current time
      parsedTimestamp = DateTime.now();
    }

    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      type: NotificationType.values.firstWhere(
            (e) => e.name == data['type'],
        orElse: () => NotificationType.general,
      ),
      timestamp: parsedTimestamp,
      isRead: data['isRead'] ?? false,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  // Convert to Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'message': message,
      'type': type.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'metadata': metadata,
    };
  }

  // Copy with
  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      metadata: metadata ?? this.metadata,
    );
  }

  // Get icon based on type
  String get icon {
    switch (type) {
      case NotificationType.appointment:
        return '📅';
      case NotificationType.medication:
        return '💊';
      case NotificationType.queue:
        return '🏥';
      case NotificationType.doctor:
        return '👨‍⚕️';
      case NotificationType.general:
        return '🔔';
    }
  }

  // Get relative time string
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}