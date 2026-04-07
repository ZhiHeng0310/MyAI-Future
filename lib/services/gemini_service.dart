import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import 'notification_service.dart';

enum GeminiRole { patient, doctor }

class GeminiService {
  static const _model   = 'gemini-2.5-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  // ── Build patient system prompt with real patient data ────────────────────
  static String _buildPatientSystem({
    required String       patientName,
    required String       diagnosis,
    required int          daysSinceVisit,
    required List<String> medications,
    String?               assignedDoctorName,
  }) {
    final medList = medications.isEmpty
        ? 'No medications currently assigned.'
        : medications.map((m) => '  - $m').join('\n');
    final doctorLine = assignedDoctorName != null && assignedDoctorName.isNotEmpty
        ? 'Assigned Doctor: Dr. $assignedDoctorName'
        : 'Assigned Doctor: Not yet assigned (clinic will handle routing).';

    return '''
You are CareLoop AI, a warm and knowledgeable medical recovery assistant for PATIENTS.

=== PATIENT PROFILE (use this for personalised, accurate responses) ===
Patient Name: $patientName
Diagnosis / Condition: $diagnosis
Days since last clinic visit: $daysSinceVisit
Current Medications:
$medList
$doctorLine

=== RESPONSE FORMAT ===
ALWAYS reply in valid JSON only — no markdown, no text outside the JSON object.
{
  "message": "<reply ≤120 words, warm tone, use patient name>",
  "risk": "low|medium|high",
  "actions": [],
  "queue_symptoms": [],
  "appointment_intent": false,
  "appointment_symptoms": [],
  "check_medications": false,
  "document_analysis": null
}

=== ACTIONS (add to actions array as needed) ===
- "alert_doctor"      → patient feels sick / unwell / bad / worse / has pain → ALWAYS trigger
- "suggest_revisit"   → symptoms not improving for days
- "remind_medication" → patient asks about or mentions medication
- "join_queue"        → patient wants to see doctor TODAY urgently
- "book_appointment"  → patient wants a FUTURE appointment (any mention of booking/scheduling)
- "check_medications" → patient asks if they took their meds today

=== RISK LEVELS ===
- high  : chest pain, cannot breathe, severe pain, emergency, stroke, unconscious
- medium: feeling sick, feel bad, feel unwell, worse, headache, fever, nausea, vomiting, pain
- low   : medication questions, general questions, feeling ok/better

=== CRITICAL RULES ===
1. If patient says they feel sick/bad/unwell/worse OR mentions ANY symptom → set risk to "medium" minimum, add "alert_doctor"
2. If patient mentions appointment/book/schedule → set appointment_intent=true, add "book_appointment", tell them to pick date from calendar
3. If patient asks about medication status/check → set check_medications=true, add "check_medications"
4. Always reference patient's ACTUAL diagnosis ($diagnosis) and medications when relevant
5. Address patient as $patientName (use first name)

=== DOCUMENT ANALYSIS (only when image is provided) ===
Set document_analysis to:
{
  "type": "medication_bill|prescription|lab_report|medical_report|other",
  "summary": "<2-3 plain-English sentences explaining the document>",
  "items": [{"name":"...","dosage":"...","frequency":"...","price":"...","instructions":"..."}],
  "total_cost": "...",
  "key_notes": ["important note 1","important note 2"],
  "patient_advice": "<what patient should know or do next>"
}
If no image → document_analysis must be null.
''';
  }

  // ── Build doctor system prompt ────────────────────────────────────────────
  static String _buildDoctorSystem({
    required String       doctorName,
    required String       doctorId,
    required List<String> patientSummaries,
  }) {
    final patients = patientSummaries.isEmpty
        ? '  No assigned patients yet.'
        : patientSummaries.map((p) => '  - $p').join('\n');
    return '''
You are CareLoop AI, a clinical assistant for DOCTORS.

=== DOCTOR PROFILE ===
Doctor: Dr. $doctorName (ID: $doctorId)
Assigned Patients:
$patients

=== RESPONSE FORMAT ===
ALWAYS reply in valid JSON only.
{
  "message": "<reply ≤120 words, professional>",
  "actions": [],
  "patient_id": null,
  "send_to_patient": null,
  "doctor_advice": null
}

=== ACTIONS ===
- "check_patient_status"     → doctor asks about a specific patient
- "send_appointment_request" → doctor wants patient to schedule appointment
- "send_patient_message"     → doctor wants to message a patient
- "respond_to_alert"         → doctor sends clinical advice after patient health alert

=== FIELDS ===
- patient_id: name/ID of target patient
- send_to_patient: exact message text to deliver to patient
- doctor_advice: clinical advice string when responding to alert

=== BEHAVIOUR ===
- Reference actual patient list above
- When responding to alert → "respond_to_alert" + populate doctor_advice
- Never fabricate patient data
''';
  }

  // ── Instance fields ───────────────────────────────────────────────────────
  final GeminiRole _role;
  final List<Map<String, dynamic>> _history = [];
  bool   _ready        = false;
  String _systemPrompt = '';

  GeminiService({GeminiRole role = GeminiRole.patient}) : _role = role;

  bool get _hasValidKey =>
      AppConfig.geminiApiKey.isNotEmpty &&
          AppConfig.geminiApiKey != 'PASTE_GEMINI_API_KEY_HERE' &&
          AppConfig.geminiApiKey.startsWith('AIza');

  // ── Session init ──────────────────────────────────────────────────────────
  Future<void> initSession({
    required String       name,
    required String       diagnosis,
    required int          daysSinceVisit,
    required List<String> medications,
    String?               role,
    String?               doctorId,
    String?               assignedDoctorName,
    List<String>?         patientSummaries,
  }) async {
    if (_ready) return;

    if (!_hasValidKey) {
      throw Exception(
          'Invalid Gemini API key. Check GEMINI_KEY in env.json.');
    }

    // Build personalised system prompt with real data
    if (_role == GeminiRole.doctor) {
      _systemPrompt = _buildDoctorSystem(
        doctorName:       name,
        doctorId:         doctorId ?? 'unknown',
        patientSummaries: patientSummaries ?? [],
      );
    } else {
      _systemPrompt = _buildPatientSystem(
        patientName:        name,
        diagnosis:          diagnosis,
        daysSinceVisit:     daysSinceVisit,
        medications:        medications,
        assignedDoctorName: assignedDoctorName,
      );
    }

    // Test connectivity
    try {
      await _rawCall(
        contents: [{'role': 'user', 'parts': [{'text': 'ping'}]}],
        maxTokens: 5,
      );
    } catch (e) {
      throw Exception('Gemini API connection failed: $e\n\n'
          'Check: 1) GEMINI_KEY in env.json  '
          '2) Gemini API enabled in Google Cloud Console  '
          '3) Internet connection');
    }

    // Seed conversation with patient context acknowledgement
    final ctx = _role == GeminiRole.doctor
        ? 'Doctor Dr. $name ready. Patients: ${(patientSummaries ?? []).join("; ")}.'
        : 'Patient $name context loaded. Diagnosis: $diagnosis. '
        'Day $daysSinceVisit. Meds: ${medications.isEmpty ? "none" : medications.join(", ")}. '
        '${assignedDoctorName != null ? "Doctor: Dr. $assignedDoctorName" : "No assigned doctor."}';

    _history
      ..add({'role': 'user',  'parts': [{'text': ctx}]})
      ..add({'role': 'model', 'parts': [{'text': _ackJson}]});

    _ready = true;
  }

  String get _ackJson => _role == GeminiRole.doctor
      ? '{"message":"Ready to assist, Doctor.","actions":[],"patient_id":null,"send_to_patient":null,"doctor_advice":null}'
      : '{"message":"Ready to help.","risk":"low","actions":[],"queue_symptoms":[],"appointment_intent":false,"appointment_symptoms":[],"check_medications":false,"document_analysis":null}';

  void reset() {
    _history.clear();
    _ready = false;
    _systemPrompt = '';
  }

  // ── Send text message ─────────────────────────────────────────────────────
  Future<GeminiResponse> sendMessage(String msg) async {
    _history.add({'role': 'user', 'parts': [{'text': msg}]});
    final r = await _call(List.from(_history));
    _history.add({'role': 'model', 'parts': [{'text': r.rawText}]});
    return r;
  }

  // ── Send with image ───────────────────────────────────────────────────────
  Future<GeminiResponse> sendMessageWithImage(
      String msg, Uint8List imageBytes, String mimeType) async {
    final base64Image = base64Encode(imageBytes);
    final userParts = [
      {'text': msg},
      {'inline_data': {'mime_type': mimeType, 'data': base64Image}},
    ];
    _history.add({'role': 'user', 'parts': userParts});

    final contentsForApi = List<Map<String, dynamic>>.from(
        _history.sublist(0, _history.length - 1));
    contentsForApi.add({'role': 'user', 'parts': userParts});

    final r = await _call(contentsForApi, max: 1000);
    _history.add({'role': 'model', 'parts': [{'text': r.rawText}]});
    return r;
  }

  // ── Check-in question generation ──────────────────────────────────────────
  Future<String> generateCheckInQuestion(String dx, int day) async {
    try {
      final t = await _rawCall(
        contents: [{'role': 'user', 'parts': [{'text':
        'Patient has $dx, day $day post-visit. '
            'Write ONE friendly check-in question under 15 words. '
            'Just the question text, no quotes or extra text.'}]}],
        maxTokens: 40,
      );
      return t.trim().isNotEmpty ? t.trim() : _defaultQ(day);
    } catch (_) {
      return _defaultQ(day);
    }
  }

  // ── Core HTTP call ────────────────────────────────────────────────────────
  Future<GeminiResponse> _call(
      List<Map<String, dynamic>> contents, {int max = 600}) async {
    if (!_hasValidKey) {
      return GeminiResponse(
        message: 'AI service not configured. Add GEMINI_KEY to env.json.',
        actions: [], rawText: '', role: _role, isError: true,
      );
    }
    try {
      final raw = await _rawCall(contents: contents, maxTokens: max);
      return GeminiResponse.fromRaw(raw, _role);
    } on _Quota {
      return _fallback(_lastUserText(contents));
    } on _Err catch (e) {
      print('❌ Gemini: ${e.msg}');
      return _role == GeminiRole.doctor
          ? GeminiResponse(message: '⚠️ ${e.msg}', actions: [], rawText: '', role: _role, isError: true)
          : _fallback(_lastUserText(contents));
    } catch (e) {
      print('❌ Gemini connection: $e');
      return _role == GeminiRole.doctor
          ? GeminiResponse(message: '⚠️ Connection error.', actions: [], rawText: '', role: _role, isError: true)
          : _fallback(_lastUserText(contents));
    }
  }

  Future<String> _rawCall({
    required List<Map<String, dynamic>> contents,
    int maxTokens = 600,
  }) async {
    if (!_hasValidKey) throw _Err('No valid API key');

    final uri  = Uri.parse('$_baseUrl?key=${AppConfig.geminiApiKey}');
    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': _systemPrompt.isNotEmpty ? _systemPrompt : 'Be a helpful assistant.'}],
      },
      'contents':           contents,
      'generationConfig': {
        'temperature':     0.4,
        'maxOutputTokens': maxTokens,
        'topP':            0.9,
      },
    });

    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));

    switch (res.statusCode) {
      case 200:
        final d     = jsonDecode(res.body) as Map;
        final cands = d['candidates'] as List?;
        if (cands == null || cands.isEmpty) throw _Err('Empty candidates');
        final parts = (cands[0]['content'] as Map?)?['parts'] as List?;
        return (parts?.first?['text'] ?? '') as String;
      case 429: throw _Quota();
      case 403: throw _Err('403 — API key invalid or Gemini API not enabled in Google Cloud Console');
      case 404: throw _Err('404 — Model "$_model" not found');
      case 400:
        try {
          final err = (jsonDecode(res.body) as Map)['error']?['message'] ?? res.body;
          throw _Err('400: $err');
        } catch (_) { throw _Err('400: ${res.body}'); }
      default:
        throw _Err('${res.statusCode}: ${res.body}');
    }
  }

  // ── Rule-based fallback (patient only) ───────────────────────────────────
  GeminiResponse _fallback(String input) {
    if (_role == GeminiRole.doctor) {
      return GeminiResponse(message: 'AI unavailable. Check API key.', actions: [], rawText: '', role: _role, isError: true);
    }
    final t = input.toLowerCase();
    if (_has(t, ['appointment','book','schedule','see doctor later','make appointment'])) {
      return GeminiResponse(
        message: 'Sure! Please pick a date from the calendar below — I\'ll book the earliest available slot for you.',
        risk: RiskLevel.low, actions: ['book_appointment'],
        appointmentIntent: true, appointmentSymptoms: _extractSymptoms(t),
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['did i take','have i taken','check my med','medication status','took my med'])) {
      return GeminiResponse(
        message: 'Let me check your medication status for today right now!',
        risk: RiskLevel.low, actions: ['check_medications'],
        checkMedications: true, queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['chest pain','can\'t breathe','shortness of breath','severe pain','emergency','fainted'])) {
      return GeminiResponse(
        message: 'This sounds very serious! I\'ve alerted your doctor immediately. Please seek emergency care if needed — call 999 or 911.',
        risk: RiskLevel.high, actions: ['alert_doctor'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['feel sick','feel bad','feel unwell','not well','getting worse','feel worse','not improving','sick','unwell','headache','fever','nausea','pain'])) {
      return GeminiResponse(
        message: 'I\'m sorry you\'re not feeling well. I\'ve notified your doctor — they will review your situation and send advice back to you shortly. Please rest.',
        risk: RiskLevel.medium, actions: ['alert_doctor'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['medication','medicine','pill','forgot','missed'])) {
      NotificationService.showImmediateReminder('CareLoop: please take your medication now.');
      return GeminiResponse(
        message: 'Staying on schedule with your medication is key to your recovery. I\'ve sent a reminder notification!',
        risk: RiskLevel.low, actions: ['remind_medication'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['better','good','great','fine','well'])) {
      return GeminiResponse(
        message: 'Great to hear you\'re feeling better! Keep up with your medications and recovery plan. 😊',
        risk: RiskLevel.low, actions: [], queueSymptoms: [], rawText: '', role: _role,
      );
    }
    return GeminiResponse(
      message: 'Thank you for checking in! Continue your recovery plan and take your medications on schedule. Let me know if anything changes.',
      risk: RiskLevel.low, actions: [], queueSymptoms: [], rawText: '', role: _role,
    );
  }

  List<String> _extractSymptoms(String t) {
    const known = ['fever','cough','headache','nausea','fatigue','pain','sore throat','dizziness','vomiting'];
    return known.where(t.contains).toList();
  }

  bool _has(String t, List<String> kw) => kw.any(t.contains);

  String _lastUserText(List<Map<String, dynamic>> c) {
    for (final m in c.reversed) {
      if (m['role'] == 'user') {
        for (final p in (m['parts'] as List? ?? [])) {
          if (p is Map && p.containsKey('text')) return p['text'] as String;
        }
      }
    }
    return '';
  }

  String _defaultQ(int day) {
    if (day <= 1) return 'How are you feeling after your visit today?';
    if (day <= 3) return 'How are your symptoms compared to yesterday?';
    if (day <= 7) return 'How is your recovery going this week?';
    return 'How have you been feeling lately?';
  }
}

class _Err   implements Exception { final String msg; const _Err(this.msg); }
class _Quota implements Exception {}

// ─── Risk Level ───────────────────────────────────────────────────────────────
enum RiskLevel { low, medium, high }

// ─── GeminiResponse ───────────────────────────────────────────────────────────
class GeminiResponse {
  final String       message;
  final RiskLevel    risk;
  final List<String> actions;
  final List<String> queueSymptoms;
  final List<String> appointmentSymptoms;
  final bool         appointmentIntent;
  final bool         checkMedications;
  final bool         isError;
  final String       rawText;
  final GeminiRole   role;
  final DocumentAnalysis? documentAnalysis;

  // Doctor-specific
  final String? patientId;
  final String? sendToPatient;
  final String? doctorAdvice;

  const GeminiResponse({
    required this.message,
    this.risk                = RiskLevel.low,
    required this.actions,
    this.queueSymptoms       = const [],
    this.appointmentSymptoms = const [],
    this.appointmentIntent   = false,
    this.checkMedications    = false,
    this.isError             = false,
    required this.rawText,
    required this.role,
    this.documentAnalysis,
    this.patientId,
    this.sendToPatient,
    this.doctorAdvice,
  });

  factory GeminiResponse.fromRaw(String raw, GeminiRole role) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'```json\s*|```\s*'), '').trim();
      final s = cleaned.indexOf('{');
      final e = cleaned.lastIndexOf('}');
      if (s == -1 || e == -1 || e <= s) throw 'no json';
      final map = jsonDecode(cleaned.substring(s, e + 1)) as Map;

      DocumentAnalysis? docAnalysis;
      if (map['document_analysis'] is Map) {
        try { docAnalysis = DocumentAnalysis.fromMap(map['document_analysis'] as Map<String,dynamic>); } catch (_) {}
      }

      return GeminiResponse(
        message:             (map['message'] as String?)?.trim() ?? 'Received.',
        risk:                _parseRisk(map['risk']),
        actions:             List<String>.from((map['actions'] as List?) ?? []),
        queueSymptoms:       List<String>.from((map['queue_symptoms'] as List?) ?? []),
        appointmentSymptoms: List<String>.from((map['appointment_symptoms'] as List?) ?? []),
        appointmentIntent:   map['appointment_intent'] == true,
        checkMedications:    map['check_medications'] == true,
        rawText:             raw,
        role:                role,
        documentAnalysis:    docAnalysis,
        patientId:           map['patient_id'] as String?,
        sendToPatient:       map['send_to_patient'] as String?,
        doctorAdvice:        map['doctor_advice'] as String?,
      );
    } catch (_) {
      return GeminiResponse(message: 'Update received.', actions: [], rawText: raw, role: role);
    }
  }

  static RiskLevel _parseRisk(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'high':   return RiskLevel.high;
      case 'medium': return RiskLevel.medium;
      default:       return RiskLevel.low;
    }
  }
}

// ─── Document Analysis ────────────────────────────────────────────────────────
class DocumentAnalysis {
  final String      type;
  final String      summary;
  final List<MedItem> items;
  final String?     totalCost;
  final List<String> keyNotes;
  final String      patientAdvice;

  const DocumentAnalysis({
    required this.type, required this.summary, required this.items,
    this.totalCost, required this.keyNotes, required this.patientAdvice,
  });

  factory DocumentAnalysis.fromMap(Map<String, dynamic> m) => DocumentAnalysis(
    type:          m['type']          as String? ?? 'other',
    summary:       m['summary']       as String? ?? '',
    items:         (m['items'] as List? ?? []).map<MedItem>((i) {
      final x = i as Map<String, dynamic>;
      return MedItem(
        name:         x['name']         as String? ?? '',
        dosage:       x['dosage']       as String? ?? '',
        frequency:    x['frequency']    as String? ?? '',
        price:        x['price']        as String?,
        instructions: x['instructions'] as String? ?? '',
      );
    }).toList(),
    totalCost:     m['total_cost']    as String?,
    keyNotes:      List<String>.from(m['key_notes'] ?? []),
    patientAdvice: m['patient_advice'] as String? ?? '',
  );
}

class MedItem {
  final String  name;
  final String  dosage;
  final String  frequency;
  final String? price;
  final String  instructions;
  const MedItem({
    required this.name, required this.dosage, required this.frequency,
    this.price, required this.instructions,
  });
}