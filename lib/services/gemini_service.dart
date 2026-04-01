import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../app_config.dart';

/// CareLoop AI Service — Gemini Flash integration.
///
/// Token optimisation strategy:
/// 1. System instruction loaded ONCE per session (Flash context caching).
/// 2. JSON-only output — no second "formatting" round-trip needed.
/// 3. maxOutputTokens: 300 — caps cost on short check-in responses.
/// 4. One-shot calls for triage & question generation (zero history overhead).
/// 5. Temperature 0.3 — consistent, factual, fewer bad regenerations.
/// 6. Compact prompt syntax (Day3,Dx:Flu) saves ~50 tokens per call.
class GeminiService {
  // ─── System Instruction ────────────────────────────────────────────────────
  // Sent ONCE when the chat session initialises, cached across turns.
  // Kept deliberately short — every extra token here multiplies per cached hit.
  static const String _systemInstruction = '''
You are CareLoop, a concise medical recovery assistant.
Rules:
- Reply ONLY in JSON: {"message":"<reply>","risk":"low|medium|high","actions":[]}
- Actions list may contain: "alert_doctor","suggest_revisit","increase_priority","remind_medication"
- message: ≤80 words, plain language, no markdown.
- risk: low=recovering well, medium=slow/uncertain, high=worsening/emergency.
- Never diagnose or prescribe. When uncertain, use suggest_revisit.
''';

  late final GenerativeModel _model;
  late final ChatSession _session;
  bool _sessionInitialised = false;

  GeminiService() {
    _model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,       // Low = factual, consistent
        maxOutputTokens: 300,   // Enough for JSON + short message
        topP: 0.85,
      ),
      systemInstruction: Content.system(_systemInstruction),
    );
    _session = _model.startChat();
  }

  // ─── Session Init ─────────────────────────────────────────────────────────
  // Call ONCE per patient session. Sends patient context as the first message
  // so it is cached — subsequent turns do NOT re-send this context.

  Future<void> initSession({
    required String name,
    required String diagnosis,
    required int daysSinceVisit,
    required List<String> medications,
  }) async {
    if (_sessionInitialised) return;

    // Compact format intentional — minimises tokens while preserving context
    final ctx = 'Patient:$name,'
        'Dx:$diagnosis,'
        'Day$daysSinceVisit,'
        'Meds:${medications.isEmpty ? "none" : medications.join(",")}.'
        ' Acknowledge with {"message":"ready","risk":"low","actions":[]}.';

    await _session.sendMessage(Content.text(ctx));
    _sessionInitialised = true;
  }

  // ─── Multi-turn Check-in ──────────────────────────────────────────────────
  // Each call builds on session history. History tokens grow per turn — keep
  // sessions short (daily check-in only, not open-ended chat).

  Future<GeminiResponse> sendMessage(String userMessage) async {
    try {
      final response = await _session.sendMessage(Content.text(userMessage));
      return GeminiResponse.fromRaw(response.text ?? '{}');
    } catch (e) {
      return GeminiResponse.error('Connection issue. Please try again.');
    }
  }

  // ─── One-shot: Symptom Triage ─────────────────────────────────────────────
  // No session history — zero history token cost. Used at queue join time.

  Future<GeminiResponse> analyzeSymptoms(
    List<String> symptoms, {
    String? diagnosis,
  }) async {
    // Compact prompt: "Symptoms:Fever,Cough.Dx:Flu.Assess risk and actions."
    final prompt = 'Symptoms:${symptoms.join(",")}.'
        '${diagnosis != null ? "Dx:$diagnosis." : ""}'
        'Assess risk and actions.';
    try {
      final r = await _model.generateContent([Content.text(prompt)]);
      return GeminiResponse.fromRaw(r.text ?? '{}');
    } catch (e) {
      return GeminiResponse.error('Analysis unavailable.');
    }
  }

  // ─── One-shot: Daily Check-in Question ───────────────────────────────────
  // Output strictly capped at 40 tokens — just a single question.

  Future<String> generateCheckInQuestion(
    String diagnosis,
    int daysSinceVisit,
  ) async {
    final prompt = 'Day$daysSinceVisit post-visit,Dx:$diagnosis.'
        'Write ONE check-in question ≤15 words. Question only, no JSON.';
    try {
      final r = await _model.generateContent(
        [Content.text(prompt)],
        generationConfig: GenerationConfig(
          maxOutputTokens: 40,
          temperature: 0.5,
        ),
      );
      return r.text?.trim() ?? 'How are you feeling today?';
    } catch (_) {
      return 'How are you feeling today?';
    }
  }
}

// ─── Response Model ──────────────────────────────────────────────────────────

enum RiskLevel { low, medium, high }

class GeminiResponse {
  final String message;
  final RiskLevel risk;
  final List<String> actions;
  final bool isError;

  const GeminiResponse({
    required this.message,
    required this.risk,
    required this.actions,
    this.isError = false,
  });

  factory GeminiResponse.fromRaw(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'```json?|```'), '').trim();
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start == -1 || end == -1) throw const FormatException('no JSON');
      final map = jsonDecode(cleaned.substring(start, end + 1))
          as Map<String, dynamic>;
      return GeminiResponse(
        message: (map['message'] as String?)?.trim() ?? 'Update received.',
        risk: _parseRisk(map['risk']),
        actions: List<String>.from((map['actions'] as List?) ?? []),
      );
    } catch (_) {
      return GeminiResponse(
        message: raw.isNotEmpty ? raw : 'Update received.',
        risk: RiskLevel.low,
        actions: [],
      );
    }
  }

  factory GeminiResponse.error(String msg) => GeminiResponse(
        message: msg,
        risk: RiskLevel.low,
        actions: [],
        isError: true,
      );

  static RiskLevel _parseRisk(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'high':   return RiskLevel.high;
      case 'medium': return RiskLevel.medium;
      default:       return RiskLevel.low;
    }
  }
}
