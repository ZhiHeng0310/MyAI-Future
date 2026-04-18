import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

enum GeminiRole { patient, doctor }
enum RiskLevel { low, medium, high }

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

class DocumentAnalysis {
  final String type;
  final String summary;
  final List<MedItem> items;
  final List<String> keyNotes;
  final String? totalCost;
  final String patientAdvice;

  const DocumentAnalysis({
    required this.type,
    required this.summary,
    required this.items,
    required this.keyNotes,
    this.totalCost,
    required this.patientAdvice,
  });

  factory DocumentAnalysis.fromJson(Map<String, dynamic> json) {
    return DocumentAnalysis(
      type: json['type'] as String? ?? 'document',
      summary: json['summary'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => MedItem.fromJson(item as Map<String, dynamic>))
          .toList() ??
          [],
      keyNotes: (json['key_notes'] as List<dynamic>?)?.cast<String>() ?? [],
      totalCost: json['total_cost'] as String?,
      patientAdvice: json['patient_advice'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'summary': summary,
    'items': items.map((i) => i.toJson()).toList(),
    'key_notes': keyNotes,
    'total_cost': totalCost,
    'patient_advice': patientAdvice,
  };
}

class MedItem {
  final String name;
  final String dosage;
  final String frequency;
  final String? price;
  final String instructions;

  const MedItem({
    required this.name,
    this.dosage = '',
    this.frequency = '',
    this.price,
    this.instructions = '',
  });

  factory MedItem.fromJson(Map<String, dynamic> json) => MedItem(
    name: json['name'] as String? ?? '',
    dosage: json['dosage'] as String? ?? '',
    frequency: json['frequency'] as String? ?? '',
    price: json['price'] as String?,
    instructions: json['instructions'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'price': price,
    'instructions': instructions,
  };
}

class GeminiResponse {
  final String message;
  final List<String> actions;
  final RiskLevel risk;
  final bool appointmentIntent;
  final List<String> appointmentSymptoms;
  final bool checkMedications;
  final bool feelUnwell;
  final List<String> unwellSymptoms;
  final String? patientId;
  final String? sendToPatient;
  final DocumentAnalysis? documentAnalysis;
  final bool isError;

  const GeminiResponse({
    required this.message,
    this.actions = const [],
    this.risk = RiskLevel.low,
    this.appointmentIntent = false,
    this.appointmentSymptoms = const [],
    this.checkMedications = false,
    this.feelUnwell = false,
    this.unwellSymptoms = const [],
    this.patientId,
    this.sendToPatient,
    this.documentAnalysis,
    this.isError = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GEMINI SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class GeminiService {
  final GeminiRole role;
  static const String _backendUrl = 'https://backend-api-362769739395.asia-southeast1.run.app/api/chat';

  bool _initialized = false;

  // 1. ADD THESE DECLARATIONS HERE:
  String? _userName;
  String? _diagnosis;
  int? _daysSinceVisit;
  List<String>? _medications;
  List<String>? _patientSummaries;
  String? _doctorId;
  List<String>? _prescribingDoctors;

  GeminiService({required this.role});

  Future<void> initSession({
    required String name,
    String? diagnosis,
    int? daysSinceVisit,
    List<String>? medications,
    List<String>? patientSummaries,
    String? doctorId,
    List<String>? prescribingDoctors,

  }) async {
    // 2. ASSIGN THEM HERE:
    _userName = name;
    _diagnosis = diagnosis;
    _daysSinceVisit = daysSinceVisit;
    _medications = medications;
    _doctorId = doctorId;
    _patientSummaries = patientSummaries;
    _prescribingDoctors = prescribingDoctors;

    _initialized = true;
    debugPrint('✅ GeminiService (Backend Mode) initialized for ${role.name}');
  }

  Future<String?> generateCheckInQuestion(String diagnosis, int days) async {
    try {
      // We send a hidden prompt to the backend to get a single question
      final response = await sendMessage(
          "Generate a brief, friendly medical check-in question for a patient with $diagnosis who had their visit $days days ago. Return ONLY the question text."
      );
      return response.message;
    } catch (e) {
      return "How are you feeling today?"; // Fallback
    }
  }

  // Text-only message to Cloud Run
  Future<GeminiResponse> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        // Inside sendMessage
        body: jsonEncode({
          "role": role == GeminiRole.patient ? "patient" : "doctor",
          "messages": [{"role": "user", "content": text}],
          "userContext": {
            "name": _userName,
            "role": role.name,
            "doctorId": _doctorId,
            "patientSummaries": _patientSummaries,
            "diagnosis": _diagnosis, // Now this won't be null!
          }
        }),
      );

      if (response.statusCode == 200) {
        // We use response.body because our backend returns a JSON string
        return _parseResponse(response.body);
      } else {
        return _parseTextHeuristically("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      return _parseTextHeuristically("Connection error: $e");
    }
  }

  // Image + Text message to Cloud Run
  Future<GeminiResponse> sendMessageWithImage(String text, Uint8List bytes, String mime) async {
    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "message": text,
          "image": base64Encode(bytes),
          "mimeType": mime,
          "userContext": {"name": _userName, "role": role.name}
        }),
      );

      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      } else {
        return _parseTextHeuristically("Image Analysis Error: ${response.statusCode}");
      }
    } catch (e) {
      return _parseTextHeuristically("Scan failed: $e");
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPONSE PARSING
  // ══════════════════════════════════════════════════════════════════════════

  GeminiResponse _parseResponse(String responseText) {
    try {
      String cleaned = responseText.trim();
      cleaned = cleaned.replaceAll(RegExp(r'```json\s*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'```\s*'), '');
      cleaned = cleaned.trim();

      final startIdx = cleaned.indexOf('{');
      final endIdx = cleaned.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonStr = cleaned.substring(startIdx, endIdx + 1);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;

        return GeminiResponse(
          message: json['message'] as String? ?? cleaned,
          actions:
          (json['actions'] as List<dynamic>?)?.cast<String>() ?? [],
          risk: _parseRisk(json['risk'] as String?),
          appointmentIntent: json['appointment_intent'] as bool? ?? false,
          appointmentSymptoms:
          (json['appointment_symptoms'] as List<dynamic>?)
              ?.cast<String>() ??
              [],
          checkMedications: json['check_medications'] as bool? ?? false,
          feelUnwell: json['feel_unwell'] as bool? ?? false,
          unwellSymptoms:
          (json['unwell_symptoms'] as List<dynamic>?)?.cast<String>() ??
              [],
          patientId: json['patient_id'] as String?,
          sendToPatient: json['send_to_patient'] as String?,
          documentAnalysis: json['document_analysis'] != null &&
              json['document_analysis'] is Map
              ? DocumentAnalysis.fromJson(
              json['document_analysis'] as Map<String, dynamic>)
              : null,
        );
      }
    } catch (e) {
      debugPrint('❌ JSON parse error: $e — heuristic fallback');
    }

    return _parseTextHeuristically(responseText);
  }

  RiskLevel _parseRisk(String? risk) {
    switch (risk?.toLowerCase()) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      default:
        return RiskLevel.low;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HEURISTIC FALLBACK
  // Important: called with the original USER text when Gemini fails,
  // so feel_unwell detection still works even without a Gemini response.
  // ══════════════════════════════════════════════════════════════════════════

  GeminiResponse _parseTextHeuristically(String text) {
    final lower = text.toLowerCase();
    final actions = <String>[];
    var risk = RiskLevel.low;
    var appointmentIntent = false;
    var checkMedications = false;
    var feelUnwell = false;
    final unwellSymptoms = <String>[];
    final appointmentSymptoms = <String>[];

    // ── Feel unwell keywords ──────────────────────────────────────────────
    const unwellKeywords = [
      'sick', 'unwell', ' pain', 'ache', 'aching', 'fever', 'headache',
      'nausea', 'nauseous', 'vomit', 'dizzy', 'dizziness', 'fatigue',
      'tired', 'weak', 'weakness', 'cough', 'sore throat', 'chest pain',
      'shortness of breath', 'breathless', 'not feeling well', 'feel bad',
      'feeling bad', 'feel terrible', 'feeling terrible', 'hurt', 'hurts',
      'hurting', 'not well', 'feeling sick', 'feel sick', 'feel unwell',
      'not feeling good', 'feeling poorly', 'stomach ache', 'backache',
      'rash', 'swollen', 'bleeding', 'burning', 'itching',
    ];

    for (final kw in unwellKeywords) {
      if (lower.contains(kw)) {
        feelUnwell = true;
        // Add readable symptom (trim leading space)
        unwellSymptoms.add(kw.trim());
        break;
      }
    }

    if (feelUnwell) {
      actions.add('alert_all_doctors');
      if (lower.contains('chest pain') ||
          lower.contains('breathless') ||
          lower.contains('shortness of breath') ||
          lower.contains('emergency') ||
          lower.contains('severe')) {
        risk = RiskLevel.high;
      } else if (lower.contains('fever') ||
          lower.contains('pain') ||
          lower.contains('vomit') ||
          lower.contains('nausea') ||
          lower.contains('dizzy')) {
        risk = RiskLevel.medium;
      } else {
        risk = RiskLevel.low;
      }
    }

    // ── Medication check ──────────────────────────────────────────────────
    if (!feelUnwell &&
        (lower.contains('medication') ||
            lower.contains('medicine') ||
            lower.contains('pills') ||
            lower.contains('meds') ||
            lower.contains('taken') ||
            lower.contains('take my'))) {
      checkMedications = true;
    }

    // ── Appointment ───────────────────────────────────────────────────────
    if (lower.contains('appointment') ||
        lower.contains('book') ||
        lower.contains('schedule') ||
        lower.contains('see the doctor') ||
        lower.contains('consult')) {
      appointmentIntent = true;
      actions.add('book_appointment');
    }

    // ── Doctor role ───────────────────────────────────────────────────────
    if (role == GeminiRole.doctor) {
      if (lower.contains('how are my patient') ||
          lower.contains('patient status') ||
          lower.contains('my patient')) {
        actions.add('review_my_patients');
      }
      if (lower.contains('recent alert') ||
          lower.contains('review alert')) {
        actions.add('review_recent_alerts');
      }
    }

    // Build a sensible message when we know patient feels unwell
    String message = text.isNotEmpty
        ? text
        : 'I\'m here to help! How can I assist you today?';

    if (feelUnwell) {
      final symptomText =
      unwellSymptoms.isNotEmpty ? unwellSymptoms.join(', ') : 'your symptoms';
      message =
      'I\'m sorry to hear you\'re not feeling well ($symptomText). '
          'I\'ve immediately alerted your doctor(s). '
          'They will review and send you advice shortly. '
          'Please rest and stay hydrated in the meantime. 🏥';
    }

    return GeminiResponse(
      message: message,
      actions: actions,
      risk: risk,
      appointmentIntent: appointmentIntent,
      appointmentSymptoms: appointmentSymptoms,
      checkMedications: checkMedications,
      feelUnwell: feelUnwell,
      unwellSymptoms: unwellSymptoms,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _initialized = false;
  }
}