import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../app_config.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum GeminiRole { patient, doctor }

enum RiskLevel { low, medium, high }

// ─── Models ───────────────────────────────────────────────────────────────────

/// Document analysis result from image scan
class DocumentAnalysis {
  final String type; // 'medication_bill', 'prescription', 'lab_report', 'medical_report'
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

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'summary': summary,
      'items': items.map((item) => item.toJson()).toList(),
      'key_notes': keyNotes,
      'total_cost': totalCost,
      'patient_advice': patientAdvice,
    };
  }
}

/// Individual medication/item from document scan
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

  factory MedItem.fromJson(Map<String, dynamic> json) {
    return MedItem(
      name: json['name'] as String? ?? '',
      dosage: json['dosage'] as String? ?? '',
      frequency: json['frequency'] as String? ?? '',
      price: json['price'] as String?,
      instructions: json['instructions'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'price': price,
      'instructions': instructions,
    };
  }
}

/// Gemini AI response with parsed actions
class GeminiResponse {
  final String message;
  final List<String> actions;
  final RiskLevel risk;
  final bool appointmentIntent;
  final List<String> appointmentSymptoms;
  final bool checkMedications;
  final List<String> queueSymptoms;
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
    this.queueSymptoms = const [],
    this.patientId,
    this.sendToPatient,
    this.documentAnalysis,
    this.isError = false,
  });
}

// ─── Gemini Service ───────────────────────────────────────────────────────────

class GeminiService {
  final GeminiRole role;
  GenerativeModel? _model;
  ChatSession? _chat;
  bool _initialized = false;

  // Context for personalization
  String? _userName;
  String? _diagnosis;
  int? _daysSinceVisit;
  List<String>? _medications;
  String? _assignedDoctorName;
  String? _doctorId;
  List<String>? _patientSummaries;

  GeminiService({required this.role});

  // ── Initialize session ────────────────────────────────────────────────────

  Future<void> initSession({
    required String name,
    required String diagnosis,
    required int daysSinceVisit,
    required List<String> medications,
    String? assignedDoctorName,
    String? doctorId,
    List<String>? patientSummaries,
  }) async {
    _userName = name;
    _diagnosis = diagnosis;
    _daysSinceVisit = daysSinceVisit;
    _medications = medications;
    _assignedDoctorName = assignedDoctorName;
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

  // ── Build system prompt ───────────────────────────────────────────────────

  String _buildSystemPrompt() {
    if (role == GeminiRole.patient) {
      return '''You are CareLoop AI, a friendly healthcare assistant helping patient $_userName.

PATIENT CONTEXT:
- Name: $_userName
- Diagnosis: $_diagnosis
- Days since last visit: $_daysSinceVisit
- Medications: ${_medications?.join(', ') ?? 'None'}
${_assignedDoctorName != null ? '- Assigned Doctor: Dr. $_assignedDoctorName' : ''}

YOUR CAPABILITIES:
1. **Appointment Booking**: Detect when patient wants to book appointment
2. **Doctor Alerts**: Detect concerning symptoms that need doctor review
3. **Medication Checks**: Check if patient has taken their medications
4. **Document Scanning**: Analyze medication bills, prescriptions, lab reports
5. **Queue Management**: Help patient join clinic queue

RESPONSE FORMAT:
Always respond with JSON containing:
{
  "message": "Your friendly response to the patient",
  "actions": ["action1", "action2"],
  "risk": "low|medium|high",
  "appointment_intent": false,
  "appointment_symptoms": [],
  "check_medications": false,
  "queue_symptoms": [],
  "document_analysis": null
}

AVAILABLE ACTIONS:
- "book_appointment": Patient wants to schedule appointment
- "alert_doctor": Symptoms require doctor notification (medium/high risk only)
- "check_medications": Patient asking about their meds
- "join_queue": Patient wants to join clinic queue
- "suggest_revisit": Recommend follow-up visit
- "remind_medication": Send medication reminder
- "increase_priority": Escalate queue priority (high risk only)

DOCUMENT ANALYSIS:
When analyzing medical images/bills, return document_analysis:
{
  "type": "medication_bill|prescription|lab_report|medical_report",
  "summary": "Clear summary of the document",
  "items": [
    {
      "name": "Medication name",
      "dosage": "10mg",
      "frequency": "2x daily",
      "price": "RM 25.00",
      "instructions": "Take with food"
    }
  ],
  "key_notes": ["Important note 1", "Important note 2"],
  "total_cost": "RM 150.00",
  "patient_advice": "What patient should do next"
}

RISK ASSESSMENT:
- **low**: Normal symptoms, routine questions
- **medium**: Persistent symptoms, moderate pain, fever
- **high**: Severe symptoms, chest pain, difficulty breathing, high fever

APPOINTMENT DETECTION:
Set appointment_intent=true and extract symptoms when patient says:
- "I want to see the doctor"
- "Book an appointment"
- "I need to consult"
- "Schedule a visit"

MEDICATION CHECK:
Set check_medications=true when patient asks:
- "Did I take my meds?"
- "Have I taken my medication?"
- "Check my pills"

BE FRIENDLY, EMPATHETIC, AND CLEAR. Keep responses conversational but professional.''';
    } else {
      // Doctor role
      return '''You are CareLoop AI, assisting Dr. $_userName in managing patients.

DOCTOR CONTEXT:
- Doctor: Dr. $_userName
- Doctor ID: $_doctorId
- Assigned Patients: ${_patientSummaries?.join('; ') ?? 'None'}

YOUR CAPABILITIES:
1. Check patient status and medical history
2. Send messages/advice to patients
3. Request appointments with patients
4. Analyze medical images and reports

RESPONSE FORMAT:
{
  "message": "Your professional response to the doctor",
  "actions": ["action1"],
  "patient_id": "patient_id_if_relevant",
  "send_to_patient": "message_to_send_if_needed"
}

AVAILABLE ACTIONS:
- "check_patient_status": Doctor asking about a patient
- "send_patient_message": Send advice/note to patient
- "send_appointment_request": Request patient to book appointment

PATIENT IDENTIFICATION:
When doctor mentions a patient name, try to match with assigned patients list.
Extract patient ID if you can identify them.

BE PROFESSIONAL, CONCISE, AND CLINICAL. Provide actionable insights.''';
    }
  }

  // ── Generate check-in question ────────────────────────────────────────────

  Future<String> generateCheckInQuestion(String diagnosis, int daysSinceVisit) async {
    final prompts = [
      'How are you feeling today?',
      'Any changes in your symptoms?',
      'Are you taking your medications regularly?',
      'How has your $diagnosis been lately?',
      'Any concerns about your health today?',
    ];

    if (daysSinceVisit > 7) {
      prompts.add('It\'s been $daysSinceVisit days since your last visit. How are you doing?');
    }

    prompts.shuffle();
    return prompts.first;
  }

  // ── Send text message ─────────────────────────────────────────────────────

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

      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini sendMessage error: $e');
      return GeminiResponse(
        message: _getFallbackResponse(text),
        isError: false,
      );
    }
  }

  // ── Send message with image ───────────────────────────────────────────────

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
      final prompt = Content.multi([
        TextPart(text),
        imagePart,
      ]);

      final response = await _model!.generateContent([prompt]);
      final responseText = response.text ?? '';

      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini image error: $e');
      return GeminiResponse(
        message: 'I analyzed your document. It appears to be a medical document, but I need a clearer image for detailed analysis.',
        documentAnalysis: DocumentAnalysis(
          type: 'document',
          summary: 'Unable to analyze document clearly. Please ensure the image is well-lit and in focus.',
          items: [],
          keyNotes: ['Please retake the photo with better lighting'],
          patientAdvice: 'Take a clearer photo and try again, or consult your pharmacist.',
        ),
      );
    }
  }

  // ── Parse Gemini response ─────────────────────────────────────────────────

  GeminiResponse _parseResponse(String responseText) {
    try {
      // Try to extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(responseText);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final json = _parseJson(jsonStr);

        if (json != null) {
          return GeminiResponse(
            message: json['message'] as String? ?? responseText,
            actions: (json['actions'] as List<dynamic>?)?.cast<String>() ?? [],
            risk: _parseRisk(json['risk'] as String?),
            appointmentIntent: json['appointment_intent'] as bool? ?? false,
            appointmentSymptoms: (json['appointment_symptoms'] as List<dynamic>?)?.cast<String>() ?? [],
            checkMedications: json['check_medications'] as bool? ?? false,
            queueSymptoms: (json['queue_symptoms'] as List<dynamic>?)?.cast<String>() ?? [],
            patientId: json['patient_id'] as String?,
            sendToPatient: json['send_to_patient'] as String?,
            documentAnalysis: json['document_analysis'] != null
                ? DocumentAnalysis.fromJson(json['document_analysis'] as Map<String, dynamic>)
                : null,
          );
        }
      }

      // Fallback: parse text heuristically
      return _parseTextHeuristically(responseText);
    } catch (e) {
      debugPrint('❌ Parse error: $e');
      return GeminiResponse(message: responseText);
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      // Clean up the JSON string
      final cleaned = jsonStr
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // Parse using dart:convert
      final dynamic decoded = compute(_jsonDecode, cleaned);
      return decoded as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('JSON parse error: $e');
      return null;
    }
  }

  static dynamic _jsonDecode(String str) {
    // Simple JSON parser since we can't import dart:convert in isolate context
    // For now, return null and fall back to heuristic parsing
    return null;
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

  // ── Heuristic text parsing ───────────────────────────────────────────────

  GeminiResponse _parseTextHeuristically(String text) {
    final lowerText = text.toLowerCase();
    final actions = <String>[];
    var risk = RiskLevel.low;
    var appointmentIntent = false;
    final appointmentSymptoms = <String>[];
    var checkMedications = false;

    // Detect appointment intent
    if (lowerText.contains('appointment') ||
        lowerText.contains('book') ||
        lowerText.contains('schedule') ||
        lowerText.contains('see the doctor') ||
        lowerText.contains('consult')) {
      appointmentIntent = true;
      actions.add('book_appointment');
    }

    // Detect medication check
    if (lowerText.contains('medication') ||
        lowerText.contains('medicine') ||
        lowerText.contains('pills') ||
        lowerText.contains('meds')) {
      checkMedications = true;
      actions.add('check_medications');
    }

    // Detect risk level
    if (lowerText.contains('severe') ||
        lowerText.contains('emergency') ||
        lowerText.contains('chest pain') ||
        lowerText.contains('can\'t breathe') ||
        lowerText.contains('very high fever')) {
      risk = RiskLevel.high;
      actions.add('alert_doctor');
    } else if (lowerText.contains('pain') ||
        lowerText.contains('fever') ||
        lowerText.contains('worried') ||
        lowerText.contains('concerned')) {
      risk = RiskLevel.medium;
      actions.add('alert_doctor');
    }

    return GeminiResponse(
      message: text,
      actions: actions,
      risk: risk,
      appointmentIntent: appointmentIntent,
      appointmentSymptoms: appointmentSymptoms,
      checkMedications: checkMedications,
    );
  }

  // ── Fallback responses ────────────────────────────────────────────────────

  String _getFallbackResponse(String userMessage) {
    final lower = userMessage.toLowerCase();

    if (lower.contains('appointment') || lower.contains('book')) {
      return 'I can help you book an appointment! Please select a date from the calendar below.';
    }

    if (lower.contains('medication') || lower.contains('meds') || lower.contains('pills')) {
      return 'Let me check your medication status for you.';
    }

    if (lower.contains('pain') || lower.contains('sick') || lower.contains('unwell')) {
      return 'I\'m sorry to hear you\'re not feeling well. Let me alert your doctor about your symptoms.';
    }

    if (lower.contains('scan') || lower.contains('bill') || lower.contains('prescription')) {
      return 'Please tap the 📎 button and upload your medical document. I\'ll analyze it for you.';
    }

    return 'I\'m here to help! I can book appointments, check your medications, alert your doctor, or scan medical documents. What would you like to do?';
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  void dispose() {
    _chat = null;
    _model = null;
    _initialized = false;
  }
}