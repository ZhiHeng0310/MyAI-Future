// lib/services/gemini_ai_service.dart
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import '../app_config.dart';

class GeminiAIService {
  static final GeminiAIService _instance = GeminiAIService._();
  static GeminiAIService get instance => _instance;
  GeminiAIService._();

  // API key loaded from app_config.dart (via env.json)

  late final GenerativeModel _model;
  bool _initialized = false;

  /// Initialize Gemini AI
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 1024,
        ),
        safetySettings: [
          SafetySetting(
            HarmCategory.harassment,
            HarmBlockThreshold.medium,
          ),
          SafetySetting(
            HarmCategory.hateSpeech,
            HarmBlockThreshold.medium,
          ),
          SafetySetting(
            HarmCategory.sexuallyExplicit,
            HarmBlockThreshold.medium,
          ),
          SafetySetting(
            HarmCategory.dangerousContent,
            HarmBlockThreshold.medium,
          ),
        ],
      );

      _initialized = true;
      debugPrint('✅ Gemini AI initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing Gemini AI: $e');
      rethrow;
    }
  }

  /// Generate response from Gemini AI
  Future<String> generateResponse(String prompt) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        return 'I apologize, but I couldn\'t generate a response. Please try again.';
      }

      return response.text!;
    } catch (e) {
      debugPrint('❌ Gemini API error: $e');
      return 'I\'m having trouble connecting right now. Please try again in a moment.';
    }
  }

  /// Generate response with conversation history
  Future<String> generateResponseWithHistory({
    required String userMessage,
    required List<ChatMessage> history,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      // Build conversation context
      final chat = _model.startChat(history: _buildHistory(history));

      final content = Content.text(userMessage);
      final response = await chat.sendMessage(content);

      if (response.text == null || response.text!.isEmpty) {
        return 'I apologize, but I couldn\'t generate a response. Please try again.';
      }

      return response.text!;
    } catch (e) {
      debugPrint('❌ Gemini chat error: $e');
      return 'I\'m having trouble connecting right now. Please try again in a moment.';
    }
  }

  /// Build conversation history for Gemini
  List<Content> _buildHistory(List<ChatMessage> messages) {
    return messages.map((msg) {
      return Content(
        msg.isUser ? 'user' : 'model',
        [TextPart(msg.text)],
      );
    }).toList();
  }

  /// Stream response (for real-time typing effect)
  Stream<String> generateResponseStream(String prompt) async* {
    if (!_initialized) {
      await initialize();
    }

    try {
      final content = [Content.text(prompt)];
      final response = _model.generateContentStream(content);

      await for (final chunk in response) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      debugPrint('❌ Gemini stream error: $e');
      yield 'I\'m having trouble connecting right now. Please try again.';
    }
  }
}

/// Chat message model for conversation history
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}