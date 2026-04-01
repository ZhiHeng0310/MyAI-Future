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

  // Web — fill this in later if you register a Web app in Firebase Console
  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'AIzaSyAiVM6V3p8lwdcCL4NmhlH8nK-SyX_uEb0',
    authDomain:        'careloop-b2ec8.firebaseapp.com',
    projectId:         'careloop-b2ec8',
    storageBucket:     'careloop-b2ec8.firebasestorage.app',
    messagingSenderId: '362769739395',
    appId:             '1:362769739395:android:af3daf6395a498475df5b6',
  );

  // Android — from your google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAiVM6V3p8lwdcCL4NmhlH8nK-SyX_uEb0',  // api_key[0].current_key
    appId:             '1:362769739395:android:af3daf6395a498475df5b6', // mobilesdk_app_id
    messagingSenderId: '362769739395',                                 // project_number
    projectId:         'careloop-b2ec8',                               // project_id
    storageBucket:     'careloop-b2ec8.firebasestorage.app',           // storage_bucket
  );

  // iOS — fill this in when you add an iOS app in Firebase Console
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'AIzaSyAiVM6V3p8lwdcCL4NmhlH8nK-SyX_uEb0',
    appId:             '1:362769739395:ios:af3daf6395a498475df5b6',
    messagingSenderId: '362769739395',
    projectId:         'careloop-b2ec8',
    storageBucket:     'careloop-b2ec8.firebasestorage.app',
    iosClientId:       'YOUR_IOS_CLIENT_ID',
    iosBundleId:       'com.careloop.app',
  );
}
