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
  // CHAT WITH BILL (for asking questions about a specific bill)
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> chatAboutBill({
    required BillAnalysis analysis,
    required String question,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content': 'Bill context: ${analysis.summary}',
          },
          {
            'role': 'user',
            'content': question,
          }
        ],
        'role': 'patient',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['message'];
    }

    throw Exception('Failed to chat: ${response.body}');
  }
}