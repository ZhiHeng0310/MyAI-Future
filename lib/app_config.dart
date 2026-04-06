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

import 'dart:convert';
import 'package:flutter/services.dart';

class AppConfig {
  static late Map<String, dynamic> _env;

  /// Load config before app starts
  static Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/env.json');
    _env = json.decode(jsonString);
  }

  /// Helper: priority order
  /// 1 dart-define
  /// 2 env.json
  /// 3 fallback default
  static String _get(String key, String fallback) {
    const fromDefine = String.fromEnvironment('');
    if (fromDefine.isNotEmpty) return fromDefine;

    return _env[key] ?? fallback;
  }

  // ─── Gemini ─────────────────────────
  static String get geminiApiKey =>
      const String.fromEnvironment('GEMINI_KEY', defaultValue: '') != ''
          ? const String.fromEnvironment('GEMINI_KEY')
          : _env['GEMINI_KEY'];

  static String get geminiModel =>
      _env['GEMINI_MODEL'] ?? 'gemini-1.5-flash';

  // ─── Clinic ─────────────────────────
  static String get defaultClinicId =>
      _env['DEFAULT_CLINIC_ID'] ?? 'clinic_main';
}