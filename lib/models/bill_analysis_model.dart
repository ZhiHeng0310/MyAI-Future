// lib/models/bill_analysis_model.dart
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Represents a single item on a medical bill
class BillItem {
  final String name;
  final int quantity;
  final double price;
  final double totalPrice;
  final String? category; // e.g., "Medicine", "Consultation", "Test"
  final String? description; // Simple explanation of what it is
  final bool? isPriceNormal; // true if price is within normal range
  final String? priceWarning; // e.g., "40% higher than average"
  final String? alternativeSuggestion; // Cheaper alternatives if available

  const BillItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    this.category,
    this.description,
    this.isPriceNormal,
    this.priceWarning,
    this.alternativeSuggestion,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 
                  ((json['price'] as num?)?.toDouble() ?? 0.0) * 
                  ((json['quantity'] as num?)?.toInt() ?? 1),
      category: json['category'] as String?,
      description: json['description'] as String?,
      isPriceNormal: json['is_price_normal'] as bool?,
      priceWarning: json['price_warning'] as String?,
      alternativeSuggestion: json['alternative_suggestion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'price': price,
    'total_price': totalPrice,
    if (category != null) 'category': category,
    if (description != null) 'description': description,
    if (isPriceNormal != null) 'is_price_normal': isPriceNormal,
    if (priceWarning != null) 'price_warning': priceWarning,
    if (alternativeSuggestion != null) 'alternative_suggestion': alternativeSuggestion,
  };
}

/// Represents a detected error or issue in the bill
class BillFlag {
  final String type; // e.g., "duplicate", "overpriced", "calculation_error"
  final String severity; // "low", "medium", "high"
  final String title;
  final String description;
  final List<String> affectedItems;
  final double? potentialSavings;

  const BillFlag({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    this.affectedItems = const [],
    this.potentialSavings,
  });

  factory BillFlag.fromJson(Map<String, dynamic> json) {
    return BillFlag(
      type: json['type'] as String? ?? 'info',
      severity: json['severity'] as String? ?? 'low',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      affectedItems: (json['affected_items'] as List<dynamic>?)?.cast<String>() ?? [],
      potentialSavings: (json['potential_savings'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'severity': severity,
    'title': title,
    'description': description,
    'affected_items': affectedItems,
    if (potentialSavings != null) 'potential_savings': potentialSavings,
  };

  Color get severityColor {
    switch (severity.toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626); // Red
      case 'medium':
        return const Color(0xFFF59E0B); // Orange
      default:
        return const Color(0xFF3B82F6); // Blue
    }
  }

  IconData get severityIcon {
    switch (severity.toLowerCase()) {
      case 'high':
        return Icons.error;
      case 'medium':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }
}

/// Complete analysis of a medical bill
class BillAnalysis {
  final String id;
  final String userId;
  final String imageUrl;
  final DateTime analyzedAt;
  final List<BillItem> items;
  final List<BillFlag> flags;
  final double subtotal;
  final double? tax;
  final double totalAmount;
  final String summary;
  final List<String> suggestions;
  final double? potentialTotalSavings;
  final String? pharmacyName;
  final String? billDate;
  final Map<String, dynamic>? rawData; // Store original OCR data

  const BillAnalysis({
    required this.id,
    required this.userId,
    required this.imageUrl,
    required this.analyzedAt,
    required this.items,
    required this.flags,
    required this.subtotal,
    this.tax,
    required this.totalAmount,
    required this.summary,
    this.suggestions = const [],
    this.potentialTotalSavings,
    this.pharmacyName,
    this.billDate,
    this.rawData,
  });

  factory BillAnalysis.fromJson(Map<String, dynamic> json) {
    return BillAnalysis(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      analyzedAt: (json['analyzed_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => BillItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
      flags: (json['flags'] as List<dynamic>?)
          ?.map((flag) => BillFlag.fromJson(flag as Map<String, dynamic>))
          .toList() ?? [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble(),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      summary: json['summary'] as String? ?? '',
      suggestions: (json['suggestions'] as List<dynamic>?)?.cast<String>() ?? [],
      potentialTotalSavings: (json['potential_total_savings'] as num?)?.toDouble(),
      pharmacyName: json['pharmacy_name'] as String?,
      billDate: json['bill_date'] as String?,
      rawData: json['raw_data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'image_url': imageUrl,
    'analyzed_at': Timestamp.fromDate(analyzedAt),
    'items': items.map((i) => i.toJson()).toList(),
    'flags': flags.map((f) => f.toJson()).toList(),
    'subtotal': subtotal,
    if (tax != null) 'tax': tax,
    'total_amount': totalAmount,
    'summary': summary,
    'suggestions': suggestions,
    if (potentialTotalSavings != null) 'potential_total_savings': potentialTotalSavings,
    if (pharmacyName != null) 'pharmacy_name': pharmacyName,
    if (billDate != null) 'bill_date': billDate,
    if (rawData != null) 'raw_data': rawData,
  };

  factory BillAnalysis.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BillAnalysis.fromJson({...data, 'id': doc.id});
  }
}

/// Extension for easier access
extension BillAnalysisExtension on BillAnalysis {
  bool get hasIssues => flags.where((f) => f.severity != 'low').isNotEmpty;
  
  List<BillFlag> get highSeverityFlags => 
    flags.where((f) => f.severity == 'high').toList();
  
  List<BillFlag> get mediumSeverityFlags => 
    flags.where((f) => f.severity == 'medium').toList();
  
  int get itemCount => items.length;
  
  String get savingsText {
    if (potentialTotalSavings == null || potentialTotalSavings! <= 0) {
      return 'No savings identified';
    }
    return 'Potential savings: RM ${potentialTotalSavings!.toStringAsFixed(2)}';
  }
}

class BillChatMessage {
  final String id;
  final String question;
  final String answer;
  final DateTime timestamp;

  const BillChatMessage({
    required this.id,
    required this.question,
    required this.answer,
    required this.timestamp,
  });

  factory BillChatMessage.fromJson(Map<String, dynamic> json) {
    return BillChatMessage(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'answer': answer,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory BillChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BillChatMessage.fromJson({...data, 'id': doc.id});
  }
}