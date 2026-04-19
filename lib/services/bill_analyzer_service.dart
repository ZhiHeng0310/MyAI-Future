// lib/services/bill_analyzer_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart' hide ApiService;
import '../models/bill_analysis_model.dart';
import 'dart:convert';

class BillAnalyzerService {
  static final BillAnalyzerService instance = BillAnalyzerService._();

  BillAnalyzerService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════════════════════
  // ANALYZE BILL IMAGE
  // ══════════════════════════════════════════════════════════════════════════

  Future<BillAnalysis> analyzeBill({
    required String userId,
    required Uint8List imageBytes,
    required String imageUrl,
  }) async {
    try {
      // Convert image to base64
      final imageBase64 = base64Encode(imageBytes);

      print('🔄 Sending bill to Cloud Run backend...');

      // ✅ CALL BACKEND API (NOT GEMINI DIRECTLY)
      final response = await ApiService.analyzeBill(
        imageBase64: imageBase64,
        userId: userId,
      );

      print('✅ Received analysis from backend');

      // Validate response has items
      if ((response['items'] as List?)?.isEmpty ?? true) {
        throw Exception(
            'No bill items detected. Please ensure the image is clear and shows a medical bill.');
      }

      // Create analysis object
      final analysis = _createBillAnalysis(
        userId: userId,
        imageUrl: imageUrl,
        analysisData: response,
      );

      // Save to Firestore
      await _saveBillAnalysis(analysis);

      return analysis;
    } catch (e) {
      debugPrint('❌ Bill analysis failed: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREATE BILL ANALYSIS OBJECT
  // ══════════════════════════════════════════════════════════════════════════

  BillAnalysis _createBillAnalysis({
    required String userId,
    required String imageUrl,
    required Map<String, dynamic> analysisData,
  }) {
    return BillAnalysis(
      id: _firestore
          .collection('bill_analyses')
          .doc()
          .id,
      userId: userId,
      imageUrl: imageUrl,
      analyzedAt: DateTime.now(),
      items: (analysisData['items'] as List<dynamic>?)
          ?.map((item) => BillItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
      flags: (analysisData['flags'] as List<dynamic>?)
          ?.map((flag) => BillFlag.fromJson(flag as Map<String, dynamic>))
          .toList() ?? [],
      subtotal: (analysisData['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (analysisData['tax'] as num?)?.toDouble(),
      totalAmount: (analysisData['total_amount'] as num?)?.toDouble() ?? 0.0,
      summary: analysisData['summary'] as String? ?? 'Analysis completed',
      suggestions: (analysisData['suggestions'] as List<dynamic>?)?.cast<
          String>() ?? [],
      potentialTotalSavings: (analysisData['potential_total_savings'] as num?)
          ?.toDouble(),
      pharmacyName: analysisData['pharmacy_name'] as String?,
      billDate: analysisData['bill_date'] as String?,
      rawData: analysisData,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SAVE TO FIRESTORE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _saveBillAnalysis(BillAnalysis analysis) async {
    try {
      await _firestore
          .collection('bill_analyses')
          .doc(analysis.id)
          .set(analysis.toJson());
      debugPrint('✅ Bill analysis saved to Firestore');
    } catch (e) {
      debugPrint('⚠️ Error saving to Firestore: $e');
      // Don't throw - we still have the analysis in memory
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GET USER'S BILL HISTORY
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<BillAnalysis>> getBillHistory(String userId) {
    return _firestore
        .collection('bill_analyses')
        .where('user_id', isEqualTo: userId)
        .orderBy('analyzed_at', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => BillAnalysis.fromFirestore(doc))
            .toList());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GET SINGLE ANALYSIS
  // ══════════════════════════════════════════════════════════════════════════

  Future<BillAnalysis?> getBillAnalysis(String analysisId) async {
    try {
      final doc = await _firestore
          .collection('bill_analyses')
          .doc(analysisId)
          .get();

      if (!doc.exists) return null;
      return BillAnalysis.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Error getting bill analysis: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DELETE ANALYSIS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> deleteBillAnalysis(String analysisId) async {
    try {
      await _firestore
          .collection('bill_analyses')
          .doc(analysisId)
          .delete();
      debugPrint('✅ Bill analysis deleted');
    } catch (e) {
      debugPrint('❌ Error deleting bill analysis: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT WITH BILL - WITH HISTORY PERSISTENCE
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> chatAboutBill({
    required BillAnalysis analysis,
    required String question,
  }) async {
    try {
      debugPrint('💬 Sending bill chat to backend...');
      debugPrint('   Question: $question');

      // ✅ Get previous chat history for context
      final chatHistory = await getChatHistory(analysis.id);

      // ✅ FIX: Use dedicated bill chat endpoint with full bill context + history
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/chat/bill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'billAnalysis': {
            'pharmacyName': analysis.pharmacyName,
            'billDate': analysis.billDate,
            'subtotal': analysis.subtotal,
            'tax': analysis.tax,
            'totalAmount': analysis.totalAmount,
            'items': analysis.items.map((item) => {
              'name': item.name,
              'quantity': item.quantity,
              'price': item.price,
              'total_price': item.totalPrice ?? item.price,
              'category': item.category,
              'description': item.description,
            }).toList(),
            'flags': analysis.flags.map((flag) => {
              'title': flag.title,
              'description': flag.description,
              'severity': flag.severity,
              'type': flag.type,
              'potential_savings': flag.potentialSavings ?? 0,
            }).toList(),
            'summary': analysis.summary,
            'suggestions': analysis.suggestions,
            'potentialTotalSavings': analysis.potentialTotalSavings ?? 0,
          },
          // ✅ NEW: Include chat history for context
          'chatHistory': chatHistory.map((msg) => {
            'question': msg.question,
            'answer': msg.answer,
          }).toList(),
        }),
      ).timeout(const Duration(seconds: 30));

      debugPrint('   Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['message'] as String;
        debugPrint('✅ Bill chat response received');

        // ✅ Save to chat history
        await _saveChatMessage(
          billId: analysis.id,
          question: question,
          answer: message,
        );

        return message;
      } else {
        debugPrint('❌ Bill chat failed: ${response.statusCode}');
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error in bill chat: $e');

      // ✅ More helpful error message
      if (e.toString().contains('timeout') || e.toString().contains('TimeoutException')) {
        return '⏱️ The request took too long. Please try asking a simpler question.';
      } else if (e.toString().contains('SocketException') || e.toString().contains('connection')) {
        return '📡 Cannot connect to the server. Please check your internet connection and try again.';
      }

      return '❌ I had trouble answering that. Please try rephrasing your question or contact support if the problem continues.';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT HISTORY MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Save a chat message to Firestore
  Future<void> _saveChatMessage({
    required String billId,
    required String question,
    required String answer,
  }) async {
    try {
      await _firestore
          .collection('bill_analyses')
          .doc(billId)
          .collection('chat_history')
          .add({
        'question': question,
        'answer': answer,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Chat message saved to history');
    } catch (e) {
      debugPrint('⚠️ Error saving chat message: $e');
      // Don't throw - chat still works without history
    }
  }

  /// Get chat history for a bill
  Future<List<BillChatMessage>> getChatHistory(String billId) async {
    try {
      final snapshot = await _firestore
          .collection('bill_analyses')
          .doc(billId)
          .collection('chat_history')
          .orderBy('timestamp', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => BillChatMessage.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Error getting chat history: $e');
      return [];
    }
  }

  /// Stream chat history for real-time updates
  Stream<List<BillChatMessage>> streamChatHistory(String billId) {
    return _firestore
        .collection('bill_analyses')
        .doc(billId)
        .collection('chat_history')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => BillChatMessage.fromFirestore(doc))
            .toList());
  }

  /// Clear chat history for a bill
  Future<void> clearChatHistory(String billId) async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('bill_analyses')
          .doc(billId)
          .collection('chat_history')
          .get();

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('✅ Chat history cleared');
    } catch (e) {
      debugPrint('❌ Error clearing chat history: $e');
      rethrow;
    }
  }
}