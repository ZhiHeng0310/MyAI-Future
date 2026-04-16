// ============================================================
//  app_config.dart
//  CareLoop — Centralised App Configuration
//
//  Keys are injected at build time via --dart-define-from-file.
//  Never hardcode secrets here.
//
//  Run / build commands:
//    flutter run   --dart-define-from-file=.env
//    flutter build apk --dart-define-from-file=.env
//
//  Copy env.example.json → .env and fill in your values.
//  .env is gitignored — never commit it.
// ============================================================
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  /// Helper getter with fallback priority:
  /// 1. dart-define
  /// 2. .env
  /// 3. fallback default

  static const String apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: "http://localhost:58469/"
  );

  static String _get(String key, String fallback) {
    const fromDefine = String.fromEnvironment('');

    // NOTE: dart-define is handled per-field below
    return dotenv.env[key] ?? fallback;
  }

  // ─── Gemini ─────────────────────────

  static String get geminiApiKey {
    const defineValue =
    String.fromEnvironment('GEMINI_KEY', defaultValue: '');

    if (defineValue.isNotEmpty) return defineValue;

    return dotenv.env['GEMINI_KEY'] ?? '';
  }

  static String get geminiModel {
    const defineValue =
    String.fromEnvironment('GEMINI_MODEL', defaultValue: '');

    if (defineValue.isNotEmpty) return defineValue;

    return dotenv.env['GEMINI_MODEL'] ?? 'gemini-2.5-flash-lite';
  }

  // ─── Clinic ─────────────────────────

  static String get defaultClinicId {
    const defineValue =
    String.fromEnvironment('DEFAULT_CLINIC_ID', defaultValue: '');

    if (defineValue.isNotEmpty) return defineValue;

    return dotenv.env['DEFAULT_CLINIC_ID'] ?? 'clinic_main';
  }
}