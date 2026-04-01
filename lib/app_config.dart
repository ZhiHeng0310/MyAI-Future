// ============================================================
//  app_config.dart
//  CareLoop — Centralised App Configuration
//
//  FILL IN YOUR KEYS HERE before running the app.
//  For production: use --dart-define at build time instead.
//
//  Example build command with dart-define:
//    flutter run --dart-define=GEMINI_KEY=AIza...
//
//  Then replace the fallback string with:
//    static const geminiApiKey = String.fromEnvironment('GEMINI_KEY');
// ============================================================

class AppConfig {
  // ─── Gemini ─────────────────────────────────────────────────────────────
  // Get your key from: https://aistudio.google.com/app/apikey
  static const String geminiApiKey = 'AIzaSyAODsBaJ_Gs6WOCuj0AiK69lB2x4eCAjQc';

  // ─── Clinic ──────────────────────────────────────────────────────────────
  // Default clinic ID used for the queue. Change for multi-clinic support.
  static const String defaultClinicId = 'clinic_main';

  // ─── Gemini Model ────────────────────────────────────────────────────────
  static const String geminiModel = 'gemini-1.5-flash'; // cost-efficient
}
