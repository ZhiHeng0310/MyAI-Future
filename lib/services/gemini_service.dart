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
          SafetySetting(
              HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
          SafetySetting(
              HarmCategory.dangerousContent, HarmBlockThreshold.medium),
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
      return '''You are CareLoop AI, a friendly healthcare assistant for patient $_userName.

PATIENT CONTEXT:
- Name: $_userName
- Diagnosis: $_diagnosis
- Days since last visit: $_daysSinceVisit
- Medications: ${_medications?.join(', ') ?? 'None'}
${_prescribingDoctors != null && _prescribingDoctors!.isNotEmpty ? '- Prescribing Doctors: ${_prescribingDoctors!.join(', ')}' : '- No doctors assigned yet'}

YOU MUST ALWAYS RESPOND WITH ONLY VALID JSON. ABSOLUTELY NO TEXT BEFORE OR AFTER THE JSON BLOCK.

RESPONSE FORMAT (return this exact structure every single time):
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

=== CAPABILITY 1: FEEL UNWELL ===
Trigger when patient mentions ANY of these: sick, unwell, pain, ache, fever, headache, nausea, vomiting, dizzy, tired, fatigue, cough, sore throat, chest pain, breathless, hurt, hurts, not feeling well, feeling bad, stomach ache, rash, swollen, bleeding, weak, burning, itching.

When triggered YOU MUST:
- Set "feel_unwell": true
- Set "actions": ["alert_all_doctors"]
- Set "risk": "high" for chest pain / breathing difficulty / unconscious / emergency
- Set "risk": "medium" for fever / moderate pain / vomiting / dizziness
- Set "risk": "low" for mild symptoms like a runny nose or slight tiredness
- List the specific symptoms mentioned in "unwell_symptoms"
- Write an empathetic message confirming the doctor alert was triggered

Good message example:
"I'm sorry to hear you're feeling unwell. I've immediately alerted your doctor(s) about your [symptoms]. They will review and respond with advice shortly. Please rest and stay hydrated in the meantime. 🏥"

=== CAPABILITY 2: MEDICATION CHECK ===
Trigger when patient asks if they took meds, medication status, pill reminders.
- Set "check_medications": true

=== CAPABILITY 3: BOOK APPOINTMENT ===
Trigger when patient wants to book, schedule, or see a doctor.
- Set "appointment_intent": true
- Set "actions": ["book_appointment"]
- Extract any reason/symptoms into "appointment_symptoms"

=== GENERAL ===
For greetings or general health questions: respond warmly. All flags false. risk = "low".

REMEMBER: Return ONLY the JSON object. Nothing else.''';
    } else {
      return '''You are CareLoop AI, assisting Dr. $_userName in managing patients.

DOCTOR CONTEXT:
- Doctor: Dr. $_userName
- Doctor ID: $_doctorId
- Patients (via prescriptions): ${_patientSummaries?.join('; ') ?? 'None'}

YOU MUST ALWAYS RESPOND WITH ONLY VALID JSON. NO TEXT BEFORE OR AFTER.

RESPONSE FORMAT:
{
  "message": "Your professional response text here",
  "actions": [],
  "patient_id": null,
  "send_to_patient": null
}

RULES:
- Add "review_my_patients" when doctor asks about patient status/overview
- Add "check_patient_status" when doctor asks about a specific patient
- Add "send_appointment_request" when doctor wants to request an appointment
- Add "review_recent_alerts" when doctor wants to see recent alerts
- Add "send_patient_message" when doctor wants to send a message
- Set "patient_id" to patient name/id hint if doctor mentions a specific patient
- Set "send_to_patient" to the message text when sending to patient

BE PROFESSIONAL AND CONCISE. Return ONLY the JSON object.''';
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
      debugPrint(
          '🤖 Gemini raw: ${responseText.substring(0, responseText.length.clamp(0, 300))}');
      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini sendMessage error: $e — using heuristic fallback');
      // Fallback runs heuristics on the original USER text so feel_unwell still fires
      return _parseTextHeuristically(text);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCAN BILLS — strict structured prompt, returns DocumentAnalysis
  // ══════════════════════════════════════════════════════════════════════════

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

      const scanPrompt = '''
You are analyzing a medication bill or pharmacy receipt.

YOUR TASK:
1. Find every medication or item on the bill.
2. For each item extract: name, dosage/strength, quantity/frequency, price.
3. Find the grand total.

Return ONLY this JSON (absolutely no text before or after):
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
    "summary": "One or two sentences summarising the bill. Example: This bill contains 3 medications totalling RM 85.50.",
    "items": [
      {
        "name": "Full medication name (brand and/or generic)",
        "dosage": "Strength e.g. 500mg",
        "frequency": "Quantity or frequency e.g. 30 tabs / twice daily",
        "price": "Price for this item e.g. RM 25.00",
        "instructions": "Usage instruction if printed on bill, else empty string"
      }
    ],
    "key_notes": [
      "Clinic or pharmacy name if visible",
      "Date of bill if visible",
      "Any other important note"
    ],
    "total_cost": "Grand total e.g. RM 85.50",
    "patient_advice": "One sentence reminding patient to take medications as prescribed and to store them properly."
  }
}

Rules:
- If a field is not visible in the image use an empty string "".
- If the image is NOT a medication bill, set type to "document" and describe what you see in summary.
- Do NOT include any text outside the JSON block.
''';

      final prompt = Content.multi([
        TextPart(scanPrompt),
        imagePart,
      ]);

      final response = await _model!.generateContent([prompt]);
      final responseText = response.text ?? '';
      debugPrint(
          '🧾 Scan raw: ${responseText.substring(0, responseText.length.clamp(0, 400))}');
      return _parseResponse(responseText);
    } catch (e) {
      debugPrint('❌ Gemini image error: $e');
      return GeminiResponse(
        message:
        '📄 I had trouble reading that image. Please try again with a clearer, well-lit photo.',
        documentAnalysis: DocumentAnalysis(
          type: 'document',
          summary:
          'Unable to analyze the document clearly. Please retake with better lighting.',
          items: [],
          keyNotes: [
            'Retake photo with better lighting',
            'Ensure all text is clearly visible',
            'Avoid glare or shadows on the bill',
          ],
          patientAdvice: 'Please take a clearer photo and try again.',
        ),
      );
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
      if (lower.contains('how are my patients') ||
          lower.contains('patient status') ||
          lower.contains('my patients')) {
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
    _chat = null;
    _model = null;
    _initialized = false;
  }
}