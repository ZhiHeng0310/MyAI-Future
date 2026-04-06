// ============================================================
//  app_config.dart
//  CareLoop — Centralised App Configuration
//
//  Keys are injected at build time via --dart-define-from-file.
//  Never hardcode secrets here.
//
//  Run / build commands:
//    flutter run   --dart-define-from-file=env.json
//    flutter build apk --dart-define-from-file=env.json
//
//  Copy env.example.json → env.json and fill in your values.
//  env.json is gitignored — never commit it.
// ============================================================

class AppConfig {
  // ─── Gemini ─────────────────────────────────────────────────────────────
  // Get your key from: https://aistudio.google.com/app/apikey
  static const String geminiApiKey =
  String.fromEnvironment('GEMINI_KEY', defaultValue: 'AIzaSyAZ0EycgzKhyYCcQUV-5K3pllHRUrSk2Ns');

  // ─── Clinic ──────────────────────────────────────────────────────────────
  static const String defaultClinicId =
  String.fromEnvironment('DEFAULT_CLINIC_ID', defaultValue: 'clinic_main');

  // ─── Gemini Model ────────────────────────────────────────────────────────
  static const String geminiModel = 'gemini-1.5-flash';
}