import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import 'notification_service.dart';

enum GeminiRole { patient, doctor }

/// Role-based Gemini service.
/// Patient mode: health guidance, risk detection, queue booking, appointment booking.
/// Doctor mode:  patient queries, status checks, send requests to patients.
class GeminiService {
  // ✅ FINAL FIX: Use gemini-1.5-flash (not -latest suffix) with v1beta
  static const _model   = 'gemini-1.5-flash';
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  // ── Patient system prompt ─────────────────────────────────────────────────
  static const _patientSystem = r'''
You are CareLoop AI, a friendly medical recovery assistant for PATIENTS.

RESPONSE FORMAT — always reply in valid JSON only:
{
  "message": "<reply ≤100 words, warm and conversational>",
  "risk": "low|medium|high",
  "actions": [],
  "queue_symptoms": [],
  "appointment_intent": false,
  "appointment_symptoms": []
}

ACTIONS:
- "alert_doctor"       — emergency or severe worsening → notify assigned doctor immediately
- "suggest_revisit"    — symptoms not improving
- "remind_medication"  — patient mentions medication/missed dose
- "join_queue"         — patient wants to see doctor urgently (today/now)
- "book_appointment"   — patient wants to schedule a future appointment

queue_symptoms: list when actions includes "join_queue"
appointment_symptoms: list when actions includes "book_appointment"
appointment_intent: true when patient mentions making/booking an appointment

RISK DETECTION:
- high: chest pain, can't breathe, unconscious, severe pain, stroke, emergency
- medium: worsening, not improving, high fever, vomiting, can't eat/sleep
- low: mild symptoms, medication questions, general recovery

IMAGE HANDLING:
- If a medication bill/receipt image is provided, read and explain: medication names, dosages, frequency, prices, instructions
- Be helpful and clear when explaining medical documents

BEHAVIOUR:
- Be warm and empathetic. Answer the actual question first.
- For "hi/hello" → greet warmly, ask how they feel.
- For food/diet questions → give practical advice.
- For medication mentions → always include "remind_medication".
- For ANY mention of "appointment", "book", "schedule", "see doctor later" → set appointment_intent=true and include "book_appointment" in actions.
- For urgent "see doctor now/today" → include "join_queue" instead.
- For high risk → include "alert_doctor" AND high risk level.
- For worsening symptoms → include "alert_doctor" with medium or high risk.
- Never diagnose. Never prescribe.
''';

  // ── Doctor system prompt ──────────────────────────────────────────────────
  static const _doctorSystem = r'''
You are CareLoop AI, a clinical assistant for DOCTORS.

RESPONSE FORMAT — always reply in valid JSON only:
{
  "message": "<reply ≤120 words, professional and concise>",
  "actions": [],
  "patient_id": null,
  "send_to_patient": null
}

ACTIONS:
- "check_patient_status"     — doctor asks about a patient → look up their latest check-ins/alerts
- "send_appointment_request" — doctor wants to ask a patient to book an appointment
- "send_patient_message"     — doctor wants to send a message to a patient via AI
- "acknowledge_alert"        — doctor acknowledges or responds to a health alert

patient_id: fill when an action targets a specific patient (use patient name or ID from context)
send_to_patient: the message text to relay to the patient (when action = send_patient_message or send_appointment_request)

IMAGE HANDLING:
- If an image is provided (medical image, report, etc.), analyze it and provide clinical observations
- Describe findings clearly and professionally

BEHAVIOUR:
- Be concise and clinical.
- When doctor asks "how is [patient]?" → include "check_patient_status".
- When doctor says "ask [patient] to book appointment" → include "send_appointment_request" and populate send_to_patient with a polite appointment request message.
- When doctor says "send message to [patient]" → include "send_patient_message".
- Reference patient data from context when available.
- Never fabricate clinical data.
''';

  final GeminiRole _role;
  final List<Map<String, dynamic>> _history = [];
  bool _ready = false;

  GeminiService({GeminiRole role = GeminiRole.patient}) : _role = role;

  String get _systemPrompt =>
      _role == GeminiRole.doctor ? _doctorSystem : _patientSystem;

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
    List<String>?         patientSummaries,
  }) async {
    if (_ready) return;

    if (!_hasValidKey) {
      throw Exception('Invalid Gemini API key. Please check app_config.dart');
    }

    String ctx;
    if (_role == GeminiRole.doctor) {
      ctx = 'Doctor: $name, ID: ${doctorId ?? "unknown"}. '
          'Assigned patients: ${patientSummaries?.join("; ") ?? "none"}. '
          'Acknowledge.';
    } else {
      ctx = 'Patient: $name, Dx: $diagnosis, Day $daysSinceVisit post-visit, '
          'Meds: ${medications.isEmpty ? "none" : medications.join(", ")}. '
          'Acknowledge.';
    }
    _history
      ..add({'role': 'user',  'parts': [{'text': ctx}]})
      ..add({'role': 'model', 'parts': [{'text': _ackJson}]});
    _ready = true;
  }

  String get _ackJson => _role == GeminiRole.doctor
      ? '{"message":"ready","actions":[],"patient_id":null,"send_to_patient":null}'
      : '{"message":"ready","risk":"low","actions":[],"queue_symptoms":[],"appointment_intent":false,"appointment_symptoms":[]}';

  // ── Reset ─────────────────────────────────────────────────────────────────
  void reset() {
    _history.clear();
    _ready = false;
  }

  // ── Send message (text only) ──────────────────────────────────────────────
  Future<GeminiResponse> sendMessage(String msg) async {
    _history.add({'role': 'user', 'parts': [{'text': msg}]});
    final r = await _call(List.from(_history));
    _history.add({'role': 'model', 'parts': [{'text': r.rawText}]});
    return r;
  }

  // ── Send message with image ───────────────────────────────────────────────
  Future<GeminiResponse> sendMessageWithImage(
      String msg, Uint8List imageBytes, String mimeType) async {
    final base64Image = base64Encode(imageBytes);
    final userParts = [
      {'text': msg},
      {
        'inline_data': {
          'mime_type': mimeType,
          'data': base64Image,
        }
      }
    ];
    _history.add({'role': 'user', 'parts': userParts});

    final contentsForApi = List<Map<String, dynamic>>.from(
        _history.sublist(0, _history.length - 1)
    );
    contentsForApi.add({'role': 'user', 'parts': userParts});

    final r = await _call(contentsForApi);
    _history.add({'role': 'model', 'parts': [{'text': r.rawText}]});
    return r;
  }

  // ── Check-in question (patient only) ──────────────────────────────────────
  Future<String> generateCheckInQuestion(String dx, int day) async {
    try {
      final t = await _raw(
        contents: [{'role': 'user', 'parts': [{'text':
        'Day $day post-visit for $dx. ONE friendly check-in question ≤15 words. Just the question.'}]}],
        maxTokens: 40,
      );
      return t.trim().isNotEmpty ? t.trim() : _defaultQ(day);
    } catch (_) { return _defaultQ(day); }
  }

  // ── HTTP ──────────────────────────────────────────────────────────────────
  Future<GeminiResponse> _call(
      List<Map<String, dynamic>> contents, {int max = 350}) async {
    if (!_hasValidKey) {
      return GeminiResponse(
        message: _role == GeminiRole.doctor
            ? 'API key not configured. Please add your Gemini API key to app_config.dart'
            : 'Unable to connect to AI service. Please check your internet connection.',
        actions: [],
        rawText: '',
        role: _role,
        isError: true,
      );
    }
    try {
      return GeminiResponse.fromRaw(
          await _raw(contents: contents, maxTokens: max), _role);
    } on _Quota {
      return _fallback(_lastUser(contents));
    }
    on _Err catch (e) {
      print('❌ Gemini API Error: ${e.msg}');
      if (_role == GeminiRole.doctor) {
        return GeminiResponse(
          message: 'API error: ${e.msg}\n\nPlease check:\n'
              '1. Your API key in app_config.dart is correct\n'
              '2. The API key has Gemini API enabled\n'
              '3. You have internet connection',
          actions: [], rawText: '', role: _role, isError: true,
        );
      }
      return _fallback(_lastUser(contents));
    }
    catch (e) {
      print('❌ Gemini Connection Error: $e');
      if (_role == GeminiRole.doctor) {
        return GeminiResponse(
          message: 'Connection error: $e\n\nPlease check your internet connection and try again.',
          actions: [], rawText: '', role: _role, isError: true,
        );
      }
      return _fallback(_lastUser(contents));
    }
  }

  Future<String> _raw({
    required List<Map<String, dynamic>> contents,
    int maxTokens = 350,
  }) async {
    if (!_hasValidKey) throw _Err('No valid API key');

    final uri  = Uri.parse('$_baseUrl?key=${AppConfig.geminiApiKey}');

    // ✅ CRITICAL: Use proper v1beta format with systemInstruction
    final body = jsonEncode({
      'system_instruction': {
        'parts': {'text': _systemPrompt}
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': maxTokens,
        'topP': 0.9
      },
    });

    print('🔵 Gemini API Request to: $_baseUrl');
    print('🔵 Using model: $_model');

    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));

    print('🔵 Gemini API Response Status: ${res.statusCode}');

    switch (res.statusCode) {
      case 200:
        final d     = jsonDecode(res.body) as Map;
        final cands = d['candidates'] as List?;
        if (cands == null || cands.isEmpty) throw _Err('Empty response');
        final parts = (cands[0]['content'] as Map?)?['parts'] as List?;
        return (parts?.first?['text'] ?? '') as String;
      case 429: throw _Quota();
      case 403: throw _Err('Gemini 403 — API key invalid or API not enabled');
      case 404:
        print('❌ 404 Error - Model: $_model, Endpoint: $_baseUrl');
        throw _Err('Gemini 404 — Model "$_model" not found. Check if model name is correct.');
      default:
        final errorBody = res.body;
        print('❌ Gemini Error Body: $errorBody');
        throw _Err('Gemini ${res.statusCode}: $errorBody');
    }
  }

  // ── Rule-based fallback (patient only) ───────────────────────────────────
  GeminiResponse _fallback(String input) {
    if (_role == GeminiRole.doctor) {
      return GeminiResponse(
        message: 'I\'m unable to connect to the AI service. '
            'Please ensure your Gemini API key is configured correctly in app_config.dart.',
        actions: [], rawText: '', role: _role, isError: true,
      );
    }
    final t = input.toLowerCase();
    if (_has(t, ['appointment','book','schedule','see doctor later','visit next'])) {
      return GeminiResponse(
        message: 'Of course! I\'ll help you book an appointment. '
            'Please select a date and time below.',
        risk: RiskLevel.low, actions: ['book_appointment'],
        queueSymptoms: [], appointmentIntent: true,
        appointmentSymptoms: _extractSymptoms(t), rawText: '', role: _role,
      );
    }
    if (_has(t, ['chest pain','can\'t breathe','shortness of breath',
      'fainted','severe pain','emergency','stroke'])) {
      return GeminiResponse(
        message: 'This sounds serious. Please seek emergency care immediately. '
            'Your doctor has been alerted.',
        risk: RiskLevel.high, actions: ['alert_doctor'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['not feeling well','feel sick','feel bad','getting worse',
      'worse','worsening','not improving'])) {
      return GeminiResponse(
        message: 'I\'m sorry you\'re not feeling well. '
            'Your doctor has been notified. Please rest and stay hydrated. '
            'If symptoms worsen quickly, seek emergency care.',
        risk: RiskLevel.medium, actions: ['alert_doctor','suggest_revisit'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['medication','medicine','pill','forgot','missed'])) {
      NotificationService.showImmediateReminder(
          'CareLoop: please take your medication now.');
      return GeminiResponse(
        message: 'It\'s important to stay on schedule with your medication. '
            'I\'ve sent you a reminder. Don\'t skip doses without consulting '
            'your doctor.',
        risk: RiskLevel.low, actions: ['remind_medication'],
        queueSymptoms: [], rawText: '', role: _role,
      );
    }
    if (_has(t, ['better','good','great','fine','well'])) {
      return GeminiResponse(
        message: 'Great to hear you\'re feeling better! Keep up your '
            'medication schedule and recovery plan. 😊',
        risk: RiskLevel.low, actions: [], queueSymptoms: [], rawText: '', role: _role,
      );
    }
    return GeminiResponse(
      message: 'Thank you for checking in. Continue your recovery plan and '
          'take medications on schedule. Let me know if anything changes.',
      risk: RiskLevel.low, actions: [], queueSymptoms: [], rawText: '', role: _role,
    );
  }

  List<String> _extractSymptoms(String text) {
    const known = ['fever','cough','headache','nausea','fatigue','pain',
      'sore throat','body ache','dizziness','vomiting'];
    return known.where(text.contains).toList();
  }

  bool _has(String t, List<String> kw) => kw.any(t.contains);
  String _lastUser(List<Map<String,dynamic>> c) {
    for (final m in c.reversed) {
      if (m['role'] == 'user') {
        final parts = m['parts'] as List?;
        if (parts != null) {
          for (final p in parts) {
            if (p is Map && p.containsKey('text')) {
              return p['text'] as String;
            }
          }
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

// ─── Response ─────────────────────────────────────────────────────────────────
enum RiskLevel { low, medium, high }

class GeminiResponse {
  final String       message;
  final RiskLevel    risk;
  final List<String> actions;
  final List<String> queueSymptoms;
  final List<String> appointmentSymptoms;
  final bool         appointmentIntent;
  final bool         isError;
  final String       rawText;
  final GeminiRole   role;

  // Doctor-specific fields
  final String? patientId;
  final String? sendToPatient;

  const GeminiResponse({
    required this.message,
    this.risk                = RiskLevel.low,
    required this.actions,
    this.queueSymptoms       = const [],
    this.appointmentSymptoms = const [],
    this.appointmentIntent   = false,
    this.isError             = false,
    required this.rawText,
    required this.role,
    this.patientId,
    this.sendToPatient,
  });

  factory GeminiResponse.fromRaw(String raw, GeminiRole role) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'```json?|```'), '').trim();
      final s = cleaned.indexOf('{'), e = cleaned.lastIndexOf('}');
      if (s == -1 || e == -1) throw '';
      final map = jsonDecode(cleaned.substring(s, e + 1)) as Map;
      return GeminiResponse(
        message:             (map['message'] as String?)?.trim() ?? 'Update received.',
        risk:                _risk(map['risk']),
        actions:             List<String>.from((map['actions'] as List?) ?? []),
        queueSymptoms:       List<String>.from((map['queue_symptoms'] as List?) ?? []),
        appointmentSymptoms: List<String>.from((map['appointment_symptoms'] as List?) ?? []),
        appointmentIntent:   map['appointment_intent'] == true,
        rawText:             raw,
        role:                role,
        patientId:           map['patient_id'] as String?,
        sendToPatient:       map['send_to_patient'] as String?,
      );
    } catch (_) {
      return GeminiResponse(
        message: raw.isNotEmpty ? raw : 'Update received.',
        actions: [], rawText: raw, role: role,
      );
    }
  }

  factory GeminiResponse.error(String msg) => GeminiResponse(
      message: msg, actions: [], rawText: '', isError: true,
      role: GeminiRole.patient);

  static RiskLevel _risk(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'high':   return RiskLevel.high;
      case 'medium': return RiskLevel.medium;
      default:       return RiskLevel.low;
    }
  }
}