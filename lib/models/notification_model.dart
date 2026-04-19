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

  // Convert from Firestore - ULTRA DEFENSIVE VERSION
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    debugPrint('\n━━━ Parsing notification ${doc.id} ━━━');

    try {
      // Step 1: Get data
      final data = doc.data() as Map<String, dynamic>?;
      debugPrint('Step 1: Data is ${data == null ? "NULL" : "present"}');

      if (data == null) {
        debugPrint('❌ FATAL: Document data is null');
        throw Exception('Document data is null');
      }

      // Step 2: Parse timestamp with ALL possible formats
      DateTime parsedTimestamp = DateTime.now(); // Safe default
      final timestampData = data['timestamp'];
      debugPrint('Step 2: Timestamp type = ${timestampData?.runtimeType ?? "null"}');

      if (timestampData == null) {
        debugPrint('  → Using current time (timestamp is null)');
        parsedTimestamp = DateTime.now();
      } else if (timestampData is Timestamp) {
        debugPrint('  → Parsing as Firestore Timestamp');
        try {
          parsedTimestamp = timestampData.toDate();
          debugPrint('  → Success: ${parsedTimestamp}');
        } catch (e) {
          debugPrint('  → Failed to convert Timestamp: $e, using now');
          parsedTimestamp = DateTime.now();
        }
      } else if (timestampData is String) {
        debugPrint('  → Parsing as ISO String: $timestampData');
        try {
          parsedTimestamp = DateTime.parse(timestampData);
          debugPrint('  → Success: ${parsedTimestamp}');
        } catch (e) {
          debugPrint('  → Failed to parse string: $e, using now');
          parsedTimestamp = DateTime.now();
        }
      } else if (timestampData is int) {
        debugPrint('  → Parsing as Unix milliseconds: $timestampData');
        try {
          parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampData);
          debugPrint('  → Success: ${parsedTimestamp}');
        } catch (e) {
          debugPrint('  → Failed to parse int: $e, using now');
          parsedTimestamp = DateTime.now();
        }
      } else {
        debugPrint('  → Unknown type ${timestampData.runtimeType}, using now');
        parsedTimestamp = DateTime.now();
      }

      // Step 3: Parse type with ultra-safe fallback
      NotificationType parsedType = NotificationType.general; // Safe default
      final typeData = data['type'];
      debugPrint('Step 3: Type data = $typeData (${typeData?.runtimeType})');

      if (typeData != null && typeData is String) {
        try {
          debugPrint('  → Attempting to parse type: $typeData');
          parsedType = NotificationType.values.firstWhere(
                (e) => e.name == typeData,
            orElse: () {
              debugPrint('  → Type "$typeData" not found, using general');
              return NotificationType.general;
            },
          );
          debugPrint('  → Parsed type: $parsedType');
        } catch (e) {
          debugPrint('  → Exception parsing type: $e, using general');
          parsedType = NotificationType.general;
        }
      } else {
        debugPrint('  → Type is null or not string, using general');
      }

      // Step 4: Parse metadata safely
      Map<String, dynamic>? parsedMetadata;
      final metadataData = data['metadata'];
      debugPrint('Step 4: Metadata is ${metadataData == null ? "null" : "present"}');

      if (metadataData != null) {
        try {
          parsedMetadata = Map<String, dynamic>.from(metadataData as Map);
          debugPrint('  → Metadata parsed successfully: ${parsedMetadata.keys}');
        } catch (e) {
          debugPrint('  → Failed to parse metadata: $e, setting to null');
          parsedMetadata = null;
        }
      }

      // Step 5: Get string fields with safe fallbacks
      final userId = (data['userId']?.toString() ?? '').trim();
      final title = (data['title']?.toString() ?? 'Notification').trim();
      final message = (data['message']?.toString() ?? '').trim();
      final isRead = data['isRead'] == true;

      debugPrint('Step 5: Fields parsed');
      debugPrint('  → userId: ${userId.isEmpty ? "EMPTY" : userId}');
      debugPrint('  → title: ${title.isEmpty ? "EMPTY" : title}');
      debugPrint('  → message length: ${message.length}');
      debugPrint('  → isRead: $isRead');

      // Step 6: Create notification
      final notification = NotificationModel(
        id: doc.id,
        userId: userId,
        title: title.isEmpty ? 'Notification' : title,
        message: message.isEmpty ? 'No message' : message,
        type: parsedType,
        timestamp: parsedTimestamp,
        isRead: isRead,
        metadata: parsedMetadata,
      );

      debugPrint('✅ SUCCESS: Notification ${doc.id} parsed successfully');
      debugPrint('   Title: "${notification.title}"');
      debugPrint('   Type: ${notification.type}');
      debugPrint('   Timestamp: ${notification.timestamp}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

      return notification;

    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR parsing notification ${doc.id}');
      debugPrint('Error: $e');
      debugPrint('Stack trace: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      rethrow;
    }
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

  // Get icon based on type - ULTRA SAFE
  String get icon {
    try {
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
    } catch (e) {
      debugPrint('⚠️ Error getting icon for type $type: $e');
      return '🔔'; // Fallback
    }
  }

  // Get relative time string - ULTRA SAFE
  String get relativeTime {
    try {
      final now = DateTime.now();
      final difference = now.difference(timestamp);

      // Handle future timestamps (clock skew or test data)
      if (difference.isNegative) {
        debugPrint('⚠️ Notification timestamp is in the future: $timestamp');
        return 'Just now';
      }

      // Handle very large differences (data corruption)
      if (difference.inDays > 3650) { // >10 years
        debugPrint('⚠️ Notification is very old: ${difference.inDays} days');
        return '${timestamp.year}';
      }

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else if (difference.inDays < 365) {
        return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
      } else {
        return '${timestamp.year}';
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error calculating relative time: $e');
      debugPrint('Stack: ${stackTrace.toString().split('\n').take(2).join('\n')}');
      return 'Recently';
    }
  }
}