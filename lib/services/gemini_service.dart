import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../app_config.dart';

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
  GenerativeModel? _model;
  ChatSession? _chat;
  bool _initialized = false;

  String? _userName;
  String? _diagnosis;
  int? _daysSinceVisit;
  List<String>? _medications;
  List<String>? _prescribingDoctors;
  String? _doctorId;
  List<String>? _patientSummaries;

  GeminiService({required this.role});

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> initSession({
    required String name,
    required String diagnosis,
    required int daysSinceVisit,
    required List<String> medications,
    List<String>? prescribingDoctors,
    String? doctorId,
    List<String>? patientSummaries,
  }) async {
    _userName = name;
    _diagnosis = diagnosis;
    _daysSinceVisit = daysSinceVisit;
    _medications = medications;
    _prescribingDoctors = prescribingDoctors;
    _doctorId = doctorId;
    _patientSummaries = patientSummaries;

    try {
      final apiKey = AppConfig.geminiApiKey;
      if (apiKey.isEmpty) {
        throw Exception('Gemini API key not configured in env.json');
      }

      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048,
        ),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
        ],
        systemInstruction: Content.text(_buildSystemPrompt()),
      );

      _chat = _model!.startChat();
      _initialized = true;

      debugPrint('✅ GeminiService initialized for ${role.name}');
    } catch (e) {
      debugPrint('❌ GeminiService init error: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYSTEM PROMPTS
  // ══════════════════════════════════════════════════════════════════════════

  String _buildSystemPrompt() {
    if (role == GeminiRole.patient) {
      return '''You are CareLoop AI, a friendly healthcare assistant helping patient $_userName.

PATIENT CONTEXT:
- Name: $_userName
- Diagnosis: $_diagnosis
- Days since last visit: $_daysSinceVisit
- Medications: ${_medications?.join(', ') ?? 'None'}
${_prescribingDoctors != null && _prescribingDoctors!.isNotEmpty ? '- Prescribing Doctors: ${_prescribingDoctors!.join(', ')}' : '- No doctors have prescribed medications yet'}

CORE RELATIONSHIP RULE:
- Patient is linked to doctors ONLY through medication prescriptions
- A patient can have multiple prescribing doctors

YOUR CAPABILITIES:

1. **Medication Check** - User asks "did I take my meds", "have I taken my pills", "medication status"
2. **Book Appointment** - User asks to book, schedule, or see a doctor  
3. **I Feel Unwell** - User says they feel sick, unwell, have pain, or symptoms
4. **Scan Bills** - User uploads a medication bill image

CRITICAL: You MUST respond with ONLY valid JSON. No text before or after the JSON block.

RESPONSE FORMAT (ALWAYS return this exact JSON structure):
{
  "message": "Your friendly response text here",
  "actions": [],
  "risk": "low",
  "appointment_intent": false,
  "appointment_symptoms": [],
  "check_medications": false,
  "feel_unwell": false,
  "unwell_symptoms": [],
  "document_analysis": null
}

RULES:
- Set "check_medications": true when user asks about medication status/adherence
- Set "appointment_intent": true when user wants to book an appointment
- Set "feel_unwell": true when user reports symptoms or feeling unwell
- Set "risk": "high" for severe symptoms (chest pain, can't breathe, emergency)
- Set "risk": "medium" for moderate symptoms (fever, pain, discomfort)
- Set "risk": "low" for general questions
- Add "alert_all_doctors" to actions when feel_unwell is true
- Add "book_appointment" to actions when appointment_intent is true
- Extract symptoms into "appointment_symptoms" and "unwell_symptoms"

For document/bill analysis, return document_analysis:
{
  "type": "medication_bill",
  "summary": "Summary text",
  "items": [{"name": "Med name", "dosage": "10mg", "frequency": "2x daily", "price": "RM 25.00", "instructions": "Take with food"}],
  "key_notes": ["Important note"],
  "total_cost": "RM 150.00",
  "patient_advice": "Advice text"
}

BE FRIENDLY AND EMPATHETIC. Keep message text conversational.''';
    } else {
      return '''You are CareLoop AI, assisting Dr. $_userName in managing patients.

DOCTOR CONTEXT:
- Doctor: Dr. $_userName
- Doctor ID: $_doctorId
- Patients (via prescriptions): ${_patientSummaries?.join('; ') ?? 'None'}

CORE RULE: Doctor can ONLY see patients they have prescribed medication to.

YOUR CAPABILITIES:
1. **How Are My Patients Today?** - review_my_patients action
2. **Check Patient Status** - check_patient_status action  
3. **Send Appointment Request** - send_appointment_request action
4. **Review Recent Alerts** - review_recent_alerts action

CRITICAL: You MUST respond with ONLY valid JSON. No text before or after.

RESPONSE FORMAT:
{
  "message": "Your professional response text here",
  "actions": [],
  "patient_id": null,
  "send_to_patient": null
}

RULES:
- Add "review_my_patients" to actions when doctor asks about patient status/overview
- Add "check_patient_status" to actions when doctor asks about a specific patient
- Add "send_appointment_request" to actions when doctor wants to request appointment
- Add "review_recent_alerts" to actions when doctor wants to see recent alerts
- Add "send_patient_message" to actions when doctor wants to send a message
- Set "patient_id" to patient name/id hint if doctor mentions a specific patient
- Set "send_to_patient" to the message text when sending to patient

BE PROFESSIONAL AND CONCISE.''';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CORE AI METHODS
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> generateCheckInQuestion(
      String diagnosis, int daysSinceVisit) async {
    final prompts = [
      'How are you feeling today?',
      'Any changes in your symptoms?',
      'Are you taking your medications regularly?',
      'How has your $diagnosis been lately?',
      'Any concerns about your health today?',
    ];

    if (daysSinceVisit > 7) {
      prompts.add(
          'It\'s been $daysSinceVisit days since your last visit. How are you doing?');
    }

    prompts.shuffle();
    return prompts.first;
  }

  Future<GeminiResponse> sendMessage(String text) async {
    if (!_initialized || _chat == null) {
      return GeminiResponse(
        message: 'I\'m having trouble connecting. Please try again.',
        isError: true,
      );
    }

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      final responseText = response.text ?? '';
      debugPrint('🤖 Gemini raw response: ${responseText.substring(0, responseText.length.clamp(0, 200))}');
      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini sendMessage error: $e');
      return GeminiResponse(
        message: _getFallbackResponse(text),
        isError: false,
      );
    }
  }

  Future<GeminiResponse> sendMessageWithImage(
      String text,
      Uint8List imageBytes,
      String mimeType,
      ) async {
    if (!_initialized || _model == null) {
      return GeminiResponse(
        message: 'I\'m having trouble connecting. Please try again.',
        isError: true,
      );
    }

    try {
      final imagePart = DataPart(mimeType, imageBytes);

      final scanPrompt = text.isEmpty || text.length < 20
          ? '''Please analyze this medication bill or prescription image.
Return ONLY valid JSON in this exact format:
{
  "message": "Here is the summary of your medication bill:",
  "actions": [],
  "risk": "low",
  "appointment_intent": false,
  "appointment_symptoms": [],
  "check_medications": false,
  "feel_unwell": false,
  "unwell_symptoms": [],
  "document_analysis": {
    "type": "medication_bill",
    "summary": "Clear summary of the bill",
    "items": [{"name": "Med name", "dosage": "dosage", "frequency": "frequency", "price": "price", "instructions": "instructions"}],
    "key_notes": ["important note"],
    "total_cost": "total amount",
    "patient_advice": "advice for patient"
  }
}'''
          : text;

      final prompt = Content.multi([
        TextPart(scanPrompt),
        imagePart,
      ]);

      final response = await _model!.generateContent([prompt]);
      final responseText = response.text ?? '';
      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini image error: $e');
      return GeminiResponse(
        message: 'I analyzed your document. Please ensure the image is clear and well-lit.',
        documentAnalysis: DocumentAnalysis(
          type: 'document',
          summary: 'Unable to analyze document clearly. Please retake with better lighting.',
          items: [],
          keyNotes: [
            'Retake photo with better lighting',
            'Ensure all text is visible'
          ],
          patientAdvice: 'Please take a clearer photo and try again.',
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPONSE PARSING — uses dart:convert for real JSON parsing
  // ══════════════════════════════════════════════════════════════════════════

  GeminiResponse _parseResponse(String responseText) {
    try {
      // Strip markdown code fences if present
      String cleaned = responseText.trim();
      cleaned = cleaned.replaceAll(RegExp(r'```json\s*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'```\s*'), '');
      cleaned = cleaned.trim();

      // Extract JSON object
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
          appointmentIntent:
          json['appointment_intent'] as bool? ?? false,
          appointmentSymptoms:
          (json['appointment_symptoms'] as List<dynamic>?)
              ?.cast<String>() ??
              [],
          checkMedications:
          json['check_medications'] as bool? ?? false,
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
      debugPrint('❌ JSON parse error: $e — falling back to heuristic');
    }

    // Fallback: heuristic parsing
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
  // HEURISTIC PARSING — fallback when JSON parsing fails
  // ══════════════════════════════════════════════════════════════════════════

  GeminiResponse _parseTextHeuristically(String text) {
    final lowerText = text.toLowerCase();
    final actions = <String>[];
    var risk = RiskLevel.low;
    var appointmentIntent = false;
    var checkMedications = false;
    var feelUnwell = false;
    final unwellSymptoms = <String>[];
    final appointmentSymptoms = <String>[];

    // Medication check
    if (lowerText.contains('medication') ||
        lowerText.contains('medicine') ||
        lowerText.contains('pills') ||
        lowerText.contains('meds') ||
        lowerText.contains('taken') ||
        lowerText.contains('take my')) {
      checkMedications = true;
      actions.add('check_medications');
    }

    // Appointment intent
    if (lowerText.contains('appointment') ||
        lowerText.contains('book') ||
        lowerText.contains('schedule') ||
        lowerText.contains('see the doctor') ||
        lowerText.contains('consult')) {
      appointmentIntent = true;
      actions.add('book_appointment');
    }

    // Feel unwell
    if (lowerText.contains('feel unwell') ||
        lowerText.contains('not feeling well') ||
        lowerText.contains('feeling sick') ||
        lowerText.contains('i\'m sick') ||
        lowerText.contains('i feel sick') ||
        lowerText.contains('something\'s wrong') ||
        lowerText.contains('pain') ||
        lowerText.contains('fever') ||
        lowerText.contains('headache') ||
        lowerText.contains('nausea')) {
      feelUnwell = true;
      actions.add('alert_all_doctors');
    }

    // Risk assessment
    if (lowerText.contains('severe') ||
        lowerText.contains('emergency') ||
        lowerText.contains('chest pain') ||
        lowerText.contains('can\'t breathe') ||
        lowerText.contains('very high fever') ||
        lowerText.contains('unconscious')) {
      risk = RiskLevel.high;
    } else if (lowerText.contains('pain') ||
        lowerText.contains('fever') ||
        lowerText.contains('worried') ||
        lowerText.contains('concerned') ||
        lowerText.contains('headache') ||
        lowerText.contains('nausea')) {
      risk = RiskLevel.medium;
    }

    // Doctor role actions
    if (role == GeminiRole.doctor) {
      if (lowerText.contains('how are my patients') ||
          lowerText.contains('patient status') ||
          lowerText.contains('my patients')) {
        actions.add('review_my_patients');
      }
      if (lowerText.contains('recent alert') ||
          lowerText.contains('review alert')) {
        actions.add('review_recent_alerts');
      }
    }

    return GeminiResponse(
      message: text.isNotEmpty
          ? text
          : 'I\'m here to help! How can I assist you today?',
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
  // FALLBACK RESPONSES
  // ══════════════════════════════════════════════════════════════════════════

  String _getFallbackResponse(String userMessage) {
    final lower = userMessage.toLowerCase();

    if (lower.contains('appointment') || lower.contains('book')) {
      return 'I can help you book an appointment! Please select a date from the calendar below.';
    }
    if (lower.contains('medication') ||
        lower.contains('meds') ||
        lower.contains('pills')) {
      return 'Let me check your medication status for you.';
    }
    if (lower.contains('unwell') ||
        lower.contains('sick') ||
        lower.contains('pain') ||
        lower.contains('fever')) {
      return 'I\'m sorry to hear you\'re not feeling well. I\'ll alert your doctors so they can provide advice.';
    }
    if (lower.contains('scan') ||
        lower.contains('bill') ||
        lower.contains('prescription')) {
      return 'Please tap the 📎 button and upload your medical document. I\'ll analyze it for you.';
    }

    return 'I\'m here to help! I can:\n'
        '📅 Book appointments\n'
        '💊 Check your medications\n'
        '🚨 Alert your doctors if you feel unwell\n'
        '📄 Scan medication bills\n\n'
        'What would you like to do?';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _chat = null;
    _model = null;
    _initialized = false;
  }
}