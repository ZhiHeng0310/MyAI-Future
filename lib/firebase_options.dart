// ============================================================
//  firebase_options.dart  (auto-generated — DO NOT EDIT manually)
//
//  All values are injected via --dart-define-from-file=env.json.
//  Copy env.example.json → env.json and fill in your Firebase
//  project values. env.json is gitignored.
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  // ── Shared Firebase values ────────────────────────────────────────────────
  static const _apiKey            = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId         = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _storageBucket     = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

  // ── Platform-specific App IDs ─────────────────────────────────────────────
  static const _appIdWeb     = String.fromEnvironment('FIREBASE_APP_ID_WEB');
  static const _appIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const _appIdIos     = String.fromEnvironment('FIREBASE_APP_ID_IOS');

  // ── iOS extras ────────────────────────────────────────────────────────────
  static const _iosClientId  = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
  static const _iosBundleId  = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.careloop.app');

  // ── Web ───────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            _apiKey,
    authDomain:        String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    projectId:         _projectId,
    storageBucket:     _storageBucket,
    messagingSenderId: _messagingSenderId,
    appId:             _appIdWeb,
  );

  // ── Android ───────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            _apiKey,
    appId:             _appIdAndroid,
    messagingSenderId: _messagingSenderId,
    projectId:         _projectId,
    storageBucket:     _storageBucket,
  );

  // ── iOS ───────────────────────────────────────────────────────────────────
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            _apiKey,
    appId:             _appIdIos,
    messagingSenderId: _messagingSenderId,
    projectId:         _projectId,
    storageBucket:     _storageBucket,
    iosClientId:       _iosClientId,
    iosBundleId:       _iosBundleId,
  );
}
