# 🔥 CareLoop — Firebase Manual Setup Guide

> Complete step-by-step guide to configure Firebase for CareLoop  
> **No FlutterFire CLI required.** Everything done through the Firebase Web Console.

---

## 📋 Prerequisites

- A Google account
- Flutter SDK installed (`flutter --version` ≥ 3.2.0)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)

---

## PART 1 — Create Your Firebase Project

### Step 1 — Open Firebase Console

1. Go to **[https://console.firebase.google.com](https://console.firebase.google.com)**
2. Sign in with your Google account
3. Click **"Add project"**

### Step 2 — Name Your Project

1. Enter project name: `careloop` (or your preferred name)
2. Your **Project ID** will be auto-generated (e.g. `careloop-a1b2c`)  
   ⚠️ **Write this down** — you'll need it many times below
3. Click **Continue**

### Step 3 — Google Analytics (Optional)

- You can **disable** Google Analytics for a hackathon — click the toggle OFF
- Click **Create project**
- Wait ~30 seconds for provisioning → Click **Continue**

---

## PART 2 — Register Your Apps

You need to register **one app per platform** you're building for.

---

### 2A — Register Android App

1. From the project overview, click the **Android icon** `</>`
2. Fill in the form:
   - **Android package name**: `com.careloop.app`  
     ⚠️ This must exactly match your `applicationId` in `android/app/build.gradle`
   - **App nickname**: `CareLoop Android` (optional)
   - **Debug signing certificate SHA-1**: skip for now (add later for Google Sign-In)
3. Click **Register app**

#### Download `google-services.json`

1. Click **Download google-services.json**
2. Place this file at: `android/app/google-services.json`  
   (Replace the existing placeholder file if any)
3. Click **Next** → **Next** → **Continue to console**

#### Update `android/app/build.gradle`

```gradle
android {
    defaultConfig {
        applicationId "com.careloop.app"   // Must match Firebase registration
        minSdk 21                           // Firebase requires minSdk 21+
        ...
    }
}

dependencies {
    // ... existing deps
}
```

#### Update `android/build.gradle` (project-level)

```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.0'  // Add this line
    }
}
```

#### Update `android/app/build.gradle` (app-level, bottom)

```gradle
// Add at the very bottom of the file
apply plugin: 'com.google.gms.google-services'
```

---

### 2B — Register iOS App

1. From project overview, click **Add app** → **iOS icon**
2. Fill in:
   - **Apple bundle ID**: `com.careloop.app`  
     ⚠️ Must match your Xcode project's Bundle Identifier
   - **App nickname**: `CareLoop iOS` (optional)
   - **App Store ID**: skip
3. Click **Register app**

#### Download `GoogleService-Info.plist`

1. Click **Download GoogleService-Info.plist**
2. In **Xcode**: drag this file into `Runner/` folder
   - Ensure **"Copy items if needed"** is checked
   - Add to target: **Runner** ✓
3. Click **Next** → **Next** → **Continue to console**

---

### 2C — Register Web App (optional, for testing in browser)

1. From project overview, click **Add app** → **Web icon** `</>`
2. App nickname: `CareLoop Web`
3. **Firebase Hosting**: leave unchecked for now
4. Click **Register app**
5. You'll see a config object — **copy it** for the next step

---

## PART 3 — Fill In `firebase_options.dart`

Open `lib/firebase_options.dart` and paste the values from each platform.

### Where to find each value:

Go to **Firebase Console → Project Settings** (gear icon, top left) → **Your apps** tab

---

### Finding Android values (from `google-services.json`)

Open the downloaded `google-services.json` and map the fields:

```json
{
  "project_info": {
    "project_id":          → projectId
    "project_number":      → messagingSenderId
    "storage_bucket":      → storageBucket
  },
  "client": [{
    "client_info": {
      "mobilesdk_app_id":  → appId
      "android_client_info": {
        "package_name":    → (your package name, not needed in options)
      }
    },
    "api_key": [{
      "current_key":       → apiKey
    }]
  }]
}
```

Paste into `firebase_options.dart`:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey:            'AIzaSy...',          // current_key
  appId:             '1:123456:android:abc123',  // mobilesdk_app_id
  messagingSenderId: '123456789',          // project_number
  projectId:         'careloop-a1b2c',     // project_id
  storageBucket:     'careloop-a1b2c.appspot.com',
);
```

---

### Finding iOS values (from `GoogleService-Info.plist`)

Open the plist in a text editor or Xcode and map:

```
API_KEY              → apiKey
GOOGLE_APP_ID        → appId
GCM_SENDER_ID        → messagingSenderId
PROJECT_ID           → projectId
STORAGE_BUCKET       → storageBucket
CLIENT_ID            → iosClientId
BUNDLE_ID            → iosBundleId
```

Paste into `firebase_options.dart`:

```dart
static const FirebaseOptions ios = FirebaseOptions(
  apiKey:            'AIzaSy...',
  appId:             '1:123456:ios:abc123',
  messagingSenderId: '123456789',
  projectId:         'careloop-a1b2c',
  storageBucket:     'careloop-a1b2c.appspot.com',
  iosClientId:       'com.googleusercontent.apps.123456-abc',
  iosBundleId:       'com.careloop.app',
);
```

---

### Finding Web values (from Console config object)

Firebase Console → Project Settings → Your apps → Web app → **Config**

```js
const firebaseConfig = {
  apiKey:            → apiKey
  authDomain:        → authDomain
  projectId:         → projectId
  storageBucket:     → storageBucket
  messagingSenderId: → messagingSenderId
  appId:             → appId
  measurementId:     → measurementId
};
```

---

## PART 4 — Enable Firebase Services

### 4A — Authentication

1. Firebase Console → **Build** → **Authentication**
2. Click **Get started**
3. Click **Sign-in method** tab
4. Click **Email/Password**
5. Toggle **Enable** → ON
6. Click **Save**

---

### 4B — Cloud Firestore

1. Firebase Console → **Build** → **Firestore Database**
2. Click **Create database**
3. Choose mode:
   - **Production mode** → recommended (rules file handles access)
   - **Test mode** → for quick hackathon prototyping (expires in 30 days)
4. Choose a **location** (pick the closest to your users):
   - Asia: `asia-southeast1` (Singapore) — good for Malaysia 🇲🇾
5. Click **Enable**

#### Deploy Firestore Security Rules

After Firestore is created:

1. Click the **Rules** tab
2. Replace the default rules with the contents of `firestore.rules` from this project
3. Click **Publish**

Or deploy via CLI:
```bash
npm install -g firebase-tools
firebase login
firebase init firestore   # select your project
firebase deploy --only firestore:rules
```

#### Create Firestore Indexes

For the queue real-time query to work, create a **composite index**:

1. Firestore → **Indexes** tab → **Add index**
2. Collection: `entries` (inside `queues/{clinicId}`)
3. Fields:
   - `priority` — Descending
   - `joinedAt` — Ascending
4. Click **Create**

> Alternatively, run the app in debug — Flutter will print a direct link to create the index automatically.

---

### 4C — Firebase Cloud Messaging (Push Notifications)

#### Android

1. Firebase Console → **Project Settings** → **Cloud Messaging** tab
2. The **Server key** is auto-created — note it for backend use
3. In `android/app/src/main/AndroidManifest.xml`, add inside `<application>`:

```xml
<service
    android:name="com.google.firebase.messaging.FirebaseMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT"/>
    </intent-filter>
</service>
```

#### iOS

1. You need an **APNs certificate** from your Apple Developer account
2. Firebase Console → Project Settings → Cloud Messaging → **iOS app configuration**
3. Upload your `.p8` APNs Auth Key:
   - Go to [Apple Developer](https://developer.apple.com) → Keys → Create key → APNs
   - Download the `.p8` file
   - Upload to Firebase + enter Key ID + Team ID
4. In Xcode: **Signing & Capabilities** → **+Capability** → add **Push Notifications** and **Background Modes** (check Remote notifications)

---

## PART 5 — Add Your Gemini API Key

1. Go to **[https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)**
2. Click **Create API key**
3. Select your Firebase project from the dropdown (links billing)
4. Copy the key

Open `lib/app_config.dart`:

```dart
static const String geminiApiKey = 'AIzaSy...YOUR_KEY_HERE...';
```

---

## PART 6 — Verify Everything Works

### Quick Checklist

```
[ ] lib/firebase_options.dart — all PASTE_ placeholders replaced
[ ] lib/app_config.dart — geminiApiKey filled in
[ ] android/app/google-services.json — downloaded and placed
[ ] ios/Runner/GoogleService-Info.plist — added to Xcode project
[ ] Firebase Auth — Email/Password enabled
[ ] Firestore — database created, rules published
[ ] Firestore index — priority DESC + joinedAt ASC created
```

### Run the App

```bash
flutter pub get
flutter run
```

Expected first-launch flow:
1. ✅ Splash screen appears (Firebase initialised successfully)
2. ✅ Login screen loads
3. ✅ Register a new account → redirected to Dashboard
4. ✅ Chat tab loads with a Gemini-generated check-in question

---

## PART 7 — Seed Test Data (Optional)

To test the medication screen without a backend, add a document manually:

1. Firestore Console → **medications** collection → **Add document**
2. Use **Auto-ID**
3. Add fields:

| Field | Type | Value |
|-------|------|-------|
| `patientId` | string | *(paste your user UID from Auth → Users)* |
| `name` | string | `Paracetamol` |
| `dosage` | string | `500mg` |
| `frequency` | string | `twice daily` |
| `reminderTimes` | array | `["08:00", "20:00"]` |
| `active` | boolean | `true` |
| `lastTaken` | null | *(leave null)* |

Repeat for more medications if needed.

---

## 🔐 Security Notes for Production

| Item | Action |
|------|--------|
| Gemini API key | Move to `--dart-define=GEMINI_KEY=xxx` and read with `String.fromEnvironment` |
| `google-services.json` | Add to `.gitignore` — never commit to public repos |
| `GoogleService-Info.plist` | Add to `.gitignore` |
| Firestore rules | Review and tighten before going live |
| Firebase App Check | Enable to prevent API abuse |

---

## 🆘 Common Errors & Fixes

| Error | Fix |
|-------|-----|
| `FirebaseException: no app` | `firebase_options.dart` values are wrong — double-check projectId |
| `PigeonFirebaseApp` crash on iOS | Ensure `GoogleService-Info.plist` is added to the **Runner target** in Xcode |
| `google-services.json` not found | File must be at `android/app/google-services.json`, not `android/` |
| Firestore permission denied | Check Firestore rules are published and user is authenticated |
| Gemini 400 error | API key is wrong or not yet activated — wait 1–2 min after creation |
| Firestore index error | Follow the link Flutter prints in debug console to auto-create the index |

---

## 📞 Useful Links

| Resource | URL |
|----------|-----|
| Firebase Console | https://console.firebase.google.com |
| Gemini API Keys | https://aistudio.google.com/app/apikey |
| FlutterFire Docs | https://firebase.flutter.dev |
| Firebase Pricing | https://firebase.google.com/pricing |
| Firestore Rules Docs | https://firebase.google.com/docs/firestore/security/get-started |

---

*CareLoop — Hackathon Project | MIT License*
