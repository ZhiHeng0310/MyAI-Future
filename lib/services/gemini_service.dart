import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart';

/// CareLoop AI — Gemini REST with rule-based fallback.
///
/// Model: gemini-2.0-flash-lite  (generous free quota)
/// Fallback: keyword-based responder — activates on 429/quota so app never breaks.
class GeminiService {
  static const String _model   = 'gemini-2.0-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const String _systemInstruction = '''
You are CareLoop, a concise medical recovery assistant.
Rules:
- Reply ONLY in valid JSON: {"message":"<reply>","risk":"low|medium|high","actions":[]}
- Actions list may contain: "alert_doctor","suggest_revisit","increase_priority","remind_medication"
- message: ≤80 words, plain language, no markdown.
- risk: low=recovering well, medium=slow/uncertain, high=worsening/emergency.
- Never diagnose or prescribe. When uncertain, escalate with suggest_revisit.
''';

  final List<Map<String, dynamic>> _history = [];
  bool _sessionInitialised = false;

  // ── Session init ──────────────────────────────────────────────────────────
  Future<void> initSession({
    required String       name,
    required String       diagnosis,
    required int          daysSinceVisit,
    required List<String> medications,
  }) async {
    if (_sessionInitialised) return;
    final ctx = 'Patient:$name, Dx:$diagnosis, Day$daysSinceVisit, '
        'Meds:${medications.isEmpty ? "none" : medications.join(",")}. '
        'Acknowledge with {"message":"ready","risk":"low","actions":[]}.';
    _history.add({'role': 'user',  'parts': [{'text': ctx}]});
    _history.add({'role': 'model', 'parts': [{'text': '{"message":"ready","risk":"low","actions":[]}'}]});
    _sessionInitialised = true;
  }

  // ── Multi-turn check-in ───────────────────────────────────────────────────
  Future<GeminiResponse> sendMessage(String userMessage) async {
    _history.add({'role': 'user', 'parts': [{'text': userMessage}]});
    final response = await _callGemini(
        contents: List<Map<String, dynamic>>.from(_history));
    _history.add({'role': 'model', 'parts': [{'text': response.rawText}]});
    return response;
  }

  // ── One-shot: symptom triage ──────────────────────────────────────────────
  Future<GeminiResponse> analyzeSymptoms(List<String> symptoms,
      {String? diagnosis}) async {
    final prompt = 'Symptoms:${symptoms.join(",")}.'
        '${diagnosis != null ? " Dx:$diagnosis." : ""}'
        ' Assess risk and suggest actions. Reply in JSON only.';
    return _callGemini(contents: [
      {'role': 'user', 'parts': [{'text': prompt}]}
    ]);
  }

  // ── One-shot: daily check-in question ─────────────────────────────────────
  Future<String> generateCheckInQuestion(
      String diagnosis, int daysSinceVisit) async {
    try {
      final prompt =
          'Day$daysSinceVisit post-visit, Dx:$diagnosis. '
          'Write ONE check-in question ≤15 words. Question only, no JSON.';
      final text = await _rawCall(
        contents:  [{'role': 'user', 'parts': [{'text': prompt}]}],
        maxTokens: 40,
      );
      return text.trim().isNotEmpty
          ? text.trim()
          : _defaultQuestion(daysSinceVisit);
    } catch (_) {
      return _defaultQuestion(daysSinceVisit);
    }
  }

  // ── HTTP caller ───────────────────────────────────────────────────────────
  Future<GeminiResponse> _callGemini({
    required List<Map<String, dynamic>> contents,
    int maxTokens = 300,
  }) async {
    // No key → straight to fallback
    if (AppConfig.geminiApiKey.isEmpty ||
        AppConfig.geminiApiKey == 'PASTE_GEMINI_API_KEY_HERE') {
      return _ruleBasedResponse(_lastUserText(contents));
    }

    try {
      final text = await _rawCall(contents: contents, maxTokens: maxTokens);
      return GeminiResponse.fromRaw(text);
    } on _QuotaException {
      // Quota hit — silent fallback, no error shown to user
      return _ruleBasedResponse(_lastUserText(contents));
    } on _GeminiException catch (e) {
      return GeminiResponse.error(e.message);
    } catch (_) {
      return _ruleBasedResponse(_lastUserText(contents));
    }
  }

  Future<String> _rawCall({
    required List<Map<String, dynamic>> contents,
    int maxTokens = 300,
  }) async {
    final uri  = Uri.parse('$_baseUrl?key=${AppConfig.geminiApiKey}');
    final body = jsonEncode({
      'system_instruction': {'parts': [{'text': _systemInstruction}]},
      'contents': contents,
      'generationConfig': {
        'temperature':     0.3,
        'maxOutputTokens': maxTokens,
        'topP':            0.85,
      },
    });

    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));

    switch (res.statusCode) {
      case 200:
        final decoded    = jsonDecode(res.body) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw _GeminiException('Empty response from Gemini.');
        }
        final parts =
        (candidates[0]['content'] as Map?)?['parts'] as List?;
        return (parts?.first?['text'] ?? '').toString();
      case 429:
        throw _QuotaException();
      case 403:
        throw _GeminiException(
            'API key invalid or Gemini not enabled (403). '
                'Visit aistudio.google.com/app/apikey');
      case 404:
        throw _GeminiException(
            'Model "$_model" not found (404). '
                'Check your API key has Gemini access.');
      default:
        final snippet = res.body.length > 200
            ? res.body.substring(0, 200)
            : res.body;
        throw _GeminiException('Gemini ${res.statusCode}: $snippet');
    }
  }

  // ── Rule-based fallback ───────────────────────────────────────────────────
  GeminiResponse _ruleBasedResponse(String input) {
    final t = input.toLowerCase();

    if (_any(t, [
      'chest pain', 'can\'t breathe', 'difficulty breathing',
      'shortness of breath', 'fainted', 'unconscious', 'severe pain',
      'emergency', 'heart attack', 'stroke',
    ])) {
      return GeminiResponse(
        message: 'This sounds serious. Please seek immediate medical '
            'attention or call emergency services. '
            'Your care team has been alerted.',
        risk:    RiskLevel.high,
        actions: ['alert_doctor', 'increase_priority'],
        rawText: '',
      );
    }

    if (_any(t, [
      'worse', 'worsening', 'not improving', 'getting bad',
      'high fever', 'vomiting', 'can\'t eat', 'can\'t sleep',
      'extremely', 'very worried', 'concerned',
    ])) {
      return GeminiResponse(
        message: 'Thank you for letting me know. Your symptoms need '
            'attention — I\'ve flagged this for your doctor. '
            'Please rest, stay hydrated, and avoid strenuous activity.',
        risk:    RiskLevel.medium,
        actions: ['suggest_revisit'],
        rawText: '',
      );
    }

    if (_any(t, [
      'medication', 'medicine', 'pill', 'tablet', 'dose',
      'forgot', 'missed', 'didn\'t take', 'skipped',
    ])) {
      return GeminiResponse(
        message: 'It\'s important to take your medication as prescribed. '
            'I\'ll send you a reminder now. If you missed a dose, '
            'take it as soon as possible unless your next dose is soon.',
        risk:    RiskLevel.low,
        actions: ['remind_medication'],
        rawText: '',
      );
    }

    if (_any(t, [
      'better', 'good', 'great', 'fine', 'well', 'improving',
      'recovered', 'normal', 'okay', 'ok', 'much better',
    ])) {
      return GeminiResponse(
        message: 'That\'s great to hear! Keep following your recovery plan, '
            'take your medications on time, rest well, and stay hydrated. '
            'You\'re doing well.',
        risk:    RiskLevel.low,
        actions: [],
        rawText: '',
      );
    }

    if (_any(t, [
      'tired', 'fatigue', 'exhausted', 'weak', 'dizzy',
      'headache', 'nausea', 'stomach',
    ])) {
      return GeminiResponse(
        message: 'Those symptoms are common during recovery. '
            'Make sure to rest, drink plenty of fluids, and eat light meals. '
            'If they persist or worsen, please contact your doctor.',
        risk:    RiskLevel.low,
        actions: [],
        rawText: '',
      );
    }

    // Generic
    return GeminiResponse(
      message: 'Thank you for checking in. Continue resting and following '
          'your medication schedule. If you notice any new or worsening '
          'symptoms, don\'t hesitate to reach out or visit the clinic.',
      risk:    RiskLevel.low,
      actions: [],
      rawText: '',
    );
  }

  bool _any(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String _lastUserText(List<Map<String, dynamic>> contents) {
    for (final c in contents.reversed) {
      if (c['role'] == 'user') {
        final parts = c['parts'] as List?;
        return (parts?.first?['text'] ?? '') as String;
      }
    }
    return '';
  }

  String _defaultQuestion(int daysSinceVisit) {
    if (daysSinceVisit <= 1) return 'How are you feeling after your visit today?';
    if (daysSinceVisit <= 3) return 'How are your symptoms compared to yesterday?';
    if (daysSinceVisit <= 7) return 'How is your recovery going this week?';
    return 'How have you been feeling lately?';
  }
}

// ─── Exceptions ───────────────────────────────────────────────────────────────
class _GeminiException  implements Exception { final String message; const _GeminiException(this.message); }
class _QuotaException   implements Exception {}

// ─── Response model ───────────────────────────────────────────────────────────
enum RiskLevel { low, medium, high }

class GeminiResponse {
  final String       message;
  final RiskLevel    risk;
  final List<String> actions;
  final bool         isError;
  final String       rawText;

  const GeminiResponse({
    required this.message,
    required this.risk,
    required this.actions,
    this.isError = false,
    this.rawText = '',
  });

  factory GeminiResponse.fromRaw(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'```json?|```'), '').trim();
      final start   = cleaned.indexOf('{');
      final end     = cleaned.lastIndexOf('}');
      if (start == -1 || end == -1) throw const FormatException('no JSON');
      final map = jsonDecode(cleaned.substring(start, end + 1))
      as Map<String, dynamic>;
      return GeminiResponse(
        message: (map['message'] as String?)?.trim() ?? 'Update received.',
        risk:    _parseRisk(map['risk']),
        actions: List<String>.from((map['actions'] as List?) ?? []),
        rawText: raw,
      );
    } catch (_) {
      return GeminiResponse(
          message: raw.isNotEmpty ? raw : 'Update received.',
          risk: RiskLevel.low, actions: [], rawText: raw);
    }
  }

  factory GeminiResponse.error(String msg) =>
      GeminiResponse(message: msg, risk: RiskLevel.low, actions: [], isError: true);

  static RiskLevel _parseRisk(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'high':   return RiskLevel.high;
      case 'medium': return RiskLevel.medium;
      default:       return RiskLevel.low;
    }
  }
}