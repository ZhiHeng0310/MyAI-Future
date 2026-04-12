// lib/services/bill_analyzer_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_config.dart';
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
    final model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 2048,
        responseMimeType: 'application/json',
      ),
    );

    final extractedBill = await _generateWithRetry(() =>
        _extractBillData(
          model: model,
          imageBytes: imageBytes,
        ),
    );

    if ((extractedBill['items'] as List?)?.isEmpty ?? true) {
      throw Exception('No bill items detected from image');
    }

    final analyzedBill = await _generateWithRetry(() =>
        _analyzeExtractedBill(
          model: model,
          extractedBill: extractedBill,
        ),
    );

    final mergedData = _mergeBillData(extractedBill, analyzedBill);

    final analysis = _createBillAnalysis(
      userId: userId,
      imageUrl: imageUrl,
      analysisData: mergedData,
    );

    await _saveBillAnalysis(analysis);

    return analysis;
  }

  Future<Map<String, dynamic>> _extractBillData({
    required GenerativeModel model,
    required Uint8List imageBytes,
  }) async {
    final prompt = '''
  Extract structured data from this medical/pharmacy bill.
  
  Return ONLY valid JSON.
  
  {
    "pharmacy_name": "string",
    "bill_date": "string",
    "items": [
      {
        "name": "string",
        "quantity": number,
        "price": number,
        "total_price": number
      }
    ],
    "subtotal": number,
    "tax": number,
    "total_amount": number
  }
  
  Rules:
  - Extract visible values only
  - Do not guess missing values
  - Return concise valid JSON only
  ''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);

    return _parseGeminiResponse(response.text ?? '');
  }

  Future<Map<String, dynamic>> _analyzeExtractedBill({
    required GenerativeModel model,
    required Map<String, dynamic> extractedBill,
  }) async {
    final prompt = '''
  Analyze this extracted medical bill data for patient-friendly insights.
  
  Bill Data:
  ${jsonEncode(extractedBill)}
  
  Return ONLY valid JSON:
  
  {
    "items": [
      {
        "name": "string",
        "category": "Medicine|Consultation|Test|Other",
        "description": "Max 8 words",
        "is_price_normal": true,
        "price_warning": "Short warning if abnormal",
        "alternative_suggestion": "Cheaper option if available"
      }
    ],
    "flags": [
      {
        "type": "duplicate|overpriced|calculation_error|missing_info",
        "severity": "low|medium|high",
        "title": "Short title",
        "description": "Patient-friendly explanation",
        "affected_items": ["Item Name"],
        "potential_savings": 0
      }
    ],
    "summary": "Overall bill assessment in 2 sentences max",
    "suggestions": [
      "Suggestion 1",
      "Suggestion 2"
    ],
    "potential_total_savings": number
  }
  
  Rules:
  - Keep text concise
  - Do not repeat extraction data
  - Focus on patient understanding
  
  IMPORTANT:
  - Return items in EXACT SAME ORDER as input
  - Do not omit any items
  - One analysis item per input item
  ''';

    final response = await model.generateContent([
      Content.text(prompt),
    ]);

    return _parseGeminiResponse(response.text ?? '');
  }

  Map<String, dynamic> _mergeBillData(
      Map<String, dynamic> extracted,
      Map<String, dynamic> analysis,
      ) {
    final extractedItems = extracted['items'] as List<dynamic>? ?? [];
    final analyzedItems = analysis['items'] as List<dynamic>? ?? [];

    final mergedItems = <Map<String, dynamic>>[];

    for (int i = 0; i < extractedItems.length; i++) {
      mergedItems.add({
        ...(extractedItems[i] as Map<String, dynamic>),
        if (i < analyzedItems.length)
          ...(analyzedItems[i] as Map<String, dynamic>),
      });
    }

    return {
      ...extracted,
      ...analysis,
      'items': mergedItems,
    };
  }

  Future<Map<String, dynamic>> _generateWithRetry(
      Future<Map<String, dynamic>> Function() fn,
      ) async {
    for (int i = 0; i < 2; i++) {
      try {
        return await fn();
      } catch (e) {
        debugPrint('Retry ${i + 1} failed: $e');
      }
    }
    throw Exception('AI generation failed after retries');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PARSE GEMINI RESPONSE
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _parseGeminiResponse(String responseText) {
    try {
      // Clean up the response
      String cleaned = responseText.trim();
      
      // Remove markdown code blocks if present
      cleaned = cleaned.replaceAll(RegExp(r'```json\s*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'```\s*'), '');
      cleaned = cleaned.trim();

      // Find JSON object
      final startIdx = cleaned.indexOf('{');
      final endIdx = cleaned.lastIndexOf('}');
      
      if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) {
        throw FormatException('No valid JSON found in response');
      }

      final jsonStr = cleaned.substring(startIdx, endIdx + 1);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      debugPrint('✅ Successfully parsed JSON response');
      return json;
    } catch (e) {
      debugPrint('❌ Error parsing response: $e');
      debugPrint('Response was: $responseText');
      
      // Throw an error if parsing fails
      throw FormatException('Invalid Gemini JSON response');
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
      id: _firestore.collection('bill_analyses').doc().id,
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
      suggestions: (analysisData['suggestions'] as List<dynamic>?)?.cast<String>() ?? [],
      potentialTotalSavings: (analysisData['potential_total_savings'] as num?)?.toDouble(),
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
        .map((snapshot) => snapshot.docs
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
    try {
      final model = GenerativeModel(
        model: AppConfig.geminiModel,
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 1024,
        ),
      );

      final billContext = '''
Bill Analysis Context:
- Pharmacy: ${analysis.pharmacyName ?? 'Unknown'}
- Date: ${analysis.billDate ?? 'Unknown'}
- Total: RM ${analysis.totalAmount.toStringAsFixed(2)}
- Items: ${analysis.items.map((i) => '${i.name} (${i.quantity}x RM${i.price})').join(', ')}
- Flags: ${analysis.flags.map((f) => '${f.title}: ${f.description}').join('; ')}
- Summary: ${analysis.summary}

User Question: $question

Instructions: You are a helpful medical bill advisor. Answer the user's question based on the bill context above. 
Be concise, friendly, and helpful. Focus on practical advice and clear explanations.
''';

      final response = await model.generateContent([Content.text(billContext)]);
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      debugPrint('❌ Error in chat: $e');
      return 'Sorry, I encountered an error. Please try again.';
    }
  }
}