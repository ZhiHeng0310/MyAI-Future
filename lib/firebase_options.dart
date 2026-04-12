// ============================================================
//  firebase_options.dart  (auto-generated — DO NOT EDIT manually)
//
//  All values are injected via --dart-define-from-file=.env.
//  Copy env.example.json → .env and fill in your Firebase
//  project values. .env is gitignored.
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAGfu6muyvZQxiD-i3FBcnVzi62UPijBSE',
    appId: '1:362769739395:web:44cf4c44059886e25df5b6',
    messagingSenderId: '362769739395',
    projectId: 'careloop-b2ec8',
    authDomain: 'careloop-b2ec8.firebaseapp.com',
    storageBucket: 'careloop-b2ec8.firebasestorage.app',
    measurementId: 'G-DRZ9D6P2GH',
  );

  // ── Web ───────────────────────────────────────────────────────────────────

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAiVM6V3p8lwdcCL4NmhlH8nK-SyX_uEb0',
    appId: '1:362769739395:android:2ace747fbbdf0c9a5df5b6',
    messagingSenderId: '362769739395',
    projectId: 'careloop-b2ec8',
    storageBucket: 'careloop-b2ec8.firebasestorage.app',
  );

  // ── Android ───────────────────────────────────────────────────────────────

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