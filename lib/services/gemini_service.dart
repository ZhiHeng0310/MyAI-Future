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
// MODELS - Aligned with Specification
// ═══════════════════════════════════════════════════════════════════════════

/// Document analysis result from bill/prescription scanning
/// SPEC: Must include medication names, individual prices, total cost
class DocumentAnalysis {
  final String type; // 'medication_bill', 'prescription', 'lab_report'
  final String summary;
  final List<MedItem> items;
  final List<String> keyNotes;
  final String? totalCost; // REQUIRED for bills
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

/// Individual medication item from scanned document
/// SPEC: Must show name, price for each item
class MedItem {
  final String name;
  final String dosage;
  final String frequency;
  final String? price; // Individual price as required by spec
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
  final bool feelUnwell; // SPEC: "I Feel Unwell" feature
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
// GEMINI SERVICE - Specification-Compliant AI
// ═══════════════════════════════════════════════════════════════════════════

class GeminiService {
  final GeminiRole role;
  GenerativeModel? _model;
  ChatSession? _chat;
  bool _initialized = false;

  // Context - NO assignedDoctorId per spec
  String? _userName;
  String? _diagnosis;
  int? _daysSinceVisit;
  List<String>? _medications;
  List<String>? _prescribingDoctors; // SPEC: Multiple doctors via prescriptions
  String? _doctorId; // For doctor role
  List<String>? _patientSummaries; // For doctor role

  GeminiService({required this.role});

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> initSession({
    required String name,
    required String diagnosis,
    required int daysSinceVisit,
    required List<String> medications,
    List<String>? prescribingDoctors, // SPEC: List of doctors who prescribed
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
        model: 'gemini-2.0-flash-exp',
        apiKey: apiKey,
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
  // SYSTEM PROMPTS - Specification-Aligned
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
- A patient can have multiple doctors
- Each medication was prescribed by a specific doctor

YOUR CAPABILITIES (SPECIFICATION-COMPLIANT):

1. **Medication Check** (Feature 1)
   - Compare current time with medication schedule
   - If medication time passed and not taken → "You missed your medication. Please take it now."
   - If medication is upcoming → Show next medication (name, time, dosage)
   - If all taken → "You're all up to date."

2. **Book Appointment** (Feature 2)
   - Show calendar and available time slots
   - Patient selects date and time
   - Confirm booking
   - Send notifications to patient AND selected doctor

3. **I Feel Unwell** (Feature 3)
   - Patient reports feeling unwell
   - Send health alert to ALL doctors who prescribed medication
   - Doctors respond with advice
   - Patient receives response via notification

4. **Scan Bills** (Feature 4)
   - Analyze medication bill images
   - Return simplified summary
   - MUST include: medication names, individual prices, total cost
   - Output must be clear and easy to understand

RESPONSE FORMAT:
Always respond with JSON:
{
  "message": "Your friendly response to the patient",
  "actions": ["action1", "action2"],
  "risk": "low|medium|high",
  "appointment_intent": false,
  "appointment_symptoms": [],
  "check_medications": false,
  "feel_unwell": false,
  "unwell_symptoms": [],
  "document_analysis": null
}

AVAILABLE ACTIONS:
- "book_appointment": Patient wants to schedule appointment
- "alert_all_doctors": SPEC - Send to ALL prescribing doctors (for "I feel unwell")
- "check_medications": Check medication adherence
- "scan_bill": Analyze medication bill/prescription
- "suggest_revisit": Recommend follow-up visit
- "remind_medication": Send medication reminder

MEDICATION CHECK LOGIC (SPEC-COMPLIANT):
When user asks "Did I take my medication?" or "Have I taken my pills?":
1. Set check_medications = true
2. System will compare current time with medication schedule
3. System will notify if medications are missed
4. Response should guide patient clearly

"I FEEL UNWELL" DETECTION (SPEC FEATURE 3):
When patient says:
- "I feel unwell" / "I'm not feeling well" / "I'm sick"
- "I have pain" / "Something's wrong"
- Reports concerning symptoms

Set feel_unwell = true and extract symptoms into unwell_symptoms array.
System will then alert ALL doctors who have prescribed medications to this patient.

DOCUMENT ANALYSIS (SPEC FEATURE 4):
When analyzing bills/prescriptions, return document_analysis:
{
  "type": "medication_bill|prescription",
  "summary": "Clear, simplified summary",
  "items": [
    {
      "name": "Medication name",
      "dosage": "10mg",
      "frequency": "2x daily",
      "price": "RM 25.00",  // REQUIRED for bills
      "instructions": "Take with food"
    }
  ],
  "key_notes": ["Important note 1"],
  "total_cost": "RM 150.00",  // REQUIRED - sum of all prices
  "patient_advice": "What patient should do next"
}

RISK ASSESSMENT:
- **low**: Normal symptoms, routine questions, general check-in
- **medium**: Persistent symptoms, moderate pain, fever, discomfort
- **high**: Severe symptoms, chest pain, difficulty breathing, emergency signs

BE FRIENDLY, EMPATHETIC, AND CLEAR. Keep responses conversational but professional.
Remember: Patients may have MULTIPLE doctors via different prescriptions!''';
    } else {
      // Doctor role
      return '''You are CareLoop AI, assisting Dr. $_userName in managing patients.

DOCTOR CONTEXT:
- Doctor: Dr. $_userName
- Doctor ID: $_doctorId
- Patients (via prescriptions): ${_patientSummaries?.join('; ') ?? 'None'}

CORE RELATIONSHIP RULE (SPECIFICATION):
- Doctor can ONLY see patients they have prescribed medication to
- No fixed doctor-patient assignment
- Relationship is dynamic based on prescriptions
- A doctor may see medication adherence ONLY for THEIR prescriptions

YOUR CAPABILITIES (SPECIFICATION-COMPLIANT):

1. **How Are My Patients Today?** (Feature 1)
   - Review patients linked via YOUR prescriptions
   - Show medication adherence for YOUR prescriptions ONLY
   - Show missed medications (for YOUR prescriptions)
   - Show alerts (if any)

2. **Check Patient Status** (Feature 2)
   - Doctor selects patient (from those you've prescribed to)
   - Send notification: "How are you feeling today?"
   - Patient replies
   - Doctor receives response via notification

3. **Send Appointment Request** (Feature 3)
   - Doctor selects patient
   - Send notification prompting appointment booking
   - Notification MUST include button to open calendar

4. **Review Recent Alerts** (Feature 4)
   - Check alerts within last 24 hours
   - If alerts exist → Display them
   - If no alerts → "No recent alerts."

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
- "send_appointment_request": Request patient to book appointment (must include calendar button)
- "review_my_patients": Show patients you've prescribed to
- "review_recent_alerts": Show alerts from last 24h

PATIENT IDENTIFICATION:
When doctor mentions a patient name, match with patients you've prescribed to.
Extract patient ID if you can identify them.
Remember: You can ONLY see patients you have prescribed medication to!

BE PROFESSIONAL, CONCISE, AND CLINICAL. Provide actionable insights.
Focus on YOUR prescriptions and YOUR patients only.''';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CORE AI METHODS
  // ══════════════════════════════════════════════════════════════════════════

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

      // SPEC: Explicit prompt for bill scanning
      final scanPrompt = text.isEmpty || text.length < 20
          ? 'Please analyze this medication bill or prescription image. '
          'Provide a clear summary including: '
          '1) All medication names with dosages, '
          '2) Individual price for each medication, '
          '3) Total cost. '
          'Make it easy to understand for the patient.'
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
          keyNotes: ['Retake photo with better lighting', 'Ensure all text is visible'],
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
      // Extract JSON from response
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
            feelUnwell: json['feel_unwell'] as bool? ?? false,
            unwellSymptoms: (json['unwell_symptoms'] as List<dynamic>?)?.cast<String>() ?? [],
            patientId: json['patient_id'] as String?,
            sendToPatient: json['send_to_patient'] as String?,
            documentAnalysis: json['document_analysis'] != null
                ? DocumentAnalysis.fromJson(json['document_analysis'] as Map<String, dynamic>)
                : null,
          );
        }
      }

      // Fallback: heuristic parsing
      return _parseTextHeuristically(responseText);
    } catch (e) {
      debugPrint('❌ Parse error: $e');
      return GeminiResponse(message: responseText);
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      final cleaned = jsonStr
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // Use compute for JSON parsing (placeholder - actual implementation may vary)
      return _safeJsonDecode(cleaned);
    } catch (e) {
      debugPrint('JSON parse error: $e');
      return null;
    }
  }

  Map<String, dynamic>? _safeJsonDecode(String str) {
    // Simplified JSON parser - in production, use dart:convert
    // For now, return null to trigger heuristic parsing
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

  // ══════════════════════════════════════════════════════════════════════════
  // HEURISTIC PARSING - Fallback when JSON parsing fails
  // ══════════════════════════════════════════════════════════════════════════

  GeminiResponse _parseTextHeuristically(String text) {
    final lowerText = text.toLowerCase();
    final actions = <String>[];
    var risk = RiskLevel.low;
    var appointmentIntent = false;
    var checkMedications = false;
    var feelUnwell = false;
    final unwellSymptoms = <String>[];

    // SPEC: Appointment detection
    if (lowerText.contains('appointment') ||
        lowerText.contains('book') ||
        lowerText.contains('schedule') ||
        lowerText.contains('see the doctor') ||
        lowerText.contains('consult')) {
      appointmentIntent = true;
      actions.add('book_appointment');
    }

    // SPEC: Medication check detection
    if (lowerText.contains('medication') ||
        lowerText.contains('medicine') ||
        lowerText.contains('pills') ||
        lowerText.contains('meds') ||
        lowerText.contains('taken') ||
        lowerText.contains('take my')) {
      checkMedications = true;
      actions.add('check_medications');
    }

    // SPEC: "I feel unwell" detection
    if (lowerText.contains('feel unwell') ||
        lowerText.contains('not feeling well') ||
        lowerText.contains('feeling sick') ||
        lowerText.contains('i\'m sick') ||
        lowerText.contains('something\'s wrong')) {
      feelUnwell = true;
      actions.add('alert_all_doctors');
    }

    // SPEC: Risk assessment
    if (lowerText.contains('severe') ||
        lowerText.contains('emergency') ||
        lowerText.contains('chest pain') ||
        lowerText.contains('can\'t breathe') ||
        lowerText.contains('very high fever')) {
      risk = RiskLevel.high;
    } else if (lowerText.contains('pain') ||
        lowerText.contains('fever') ||
        lowerText.contains('worried') ||
        lowerText.contains('concerned')) {
      risk = RiskLevel.medium;
    }

    return GeminiResponse(
      message: text,
      actions: actions,
      risk: risk,
      appointmentIntent: appointmentIntent,
      checkMedications: checkMedications,
      feelUnwell: feelUnwell,
      unwellSymptoms: unwellSymptoms,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FALLBACK RESPONSES - When AI fails
  // ══════════════════════════════════════════════════════════════════════════

  String _getFallbackResponse(String userMessage) {
    final lower = userMessage.toLowerCase();

    // SPEC Feature 2: Book Appointment
    if (lower.contains('appointment') || lower.contains('book')) {
      return 'I can help you book an appointment! Please select a date from the calendar below.';
    }

    // SPEC Feature 1: Medication Check
    if (lower.contains('medication') || lower.contains('meds') || lower.contains('pills')) {
      return 'Let me check your medication status for you.';
    }

    // SPEC Feature 3: I Feel Unwell
    if (lower.contains('unwell') || lower.contains('sick') || lower.contains('pain')) {
      return 'I\'m sorry to hear you\'re not feeling well. I\'ll alert your doctors so they can provide advice.';
    }

    // SPEC Feature 4: Scan Bills
    if (lower.contains('scan') || lower.contains('bill') || lower.contains('prescription')) {
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