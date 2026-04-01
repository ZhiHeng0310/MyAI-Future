# 🏥 CareLoop

> Agentic AI Patient Care System — **Flutter · Firebase · Gemini Flash**  

---

## 📁 Project Structure

```
careloop_v2/
├── firebase_setup.md              ← 📖 READ THIS FIRST
├── firebase_options.dart          ← 🔴 Fill in your Firebase values
├── firestore.rules                ← Deploy to Firestore console
├── pubspec.yaml
│
└── lib/
    ├── main.dart
    ├── app_config.dart            ← 🔴 Add Gemini API key here
    ├── firebase_options.dart      ← 🔴 Add Firebase config here
    │
    ├── models/                    patient, queue, medication, checkin
    ├── services/
    │   ├── gemini_service.dart    Gemini Flash + token-optimised prompts
    │   └── firestore_service.dart All Firestore reads/writes
    ├── providers/                 auth, queue, medication, chat (state)
    ├── screens/
    │   ├── splash_screen.dart
    │   ├── auth/                  login, register
    │   ├── home/                  dashboard + bottom nav
    │   ├── chat/                  AI Recovery Agent
    │   ├── queue/                 Smart Queue
    │   └── medications/           Adherence tracker
    └── widgets/                   cl_button, cl_text_field, stat_card, risk_badge
```

---

## 🔑 Key Files to Edit

| File | What to add |
|------|------------|
| `lib/firebase_options.dart` | Firebase project config (apiKey, appId, projectId, etc.) |
| `lib/app_config.dart` | Gemini API key |
| `android/app/google-services.json` | Downloaded from Firebase Console |
| `ios/Runner/GoogleService-Info.plist` | Downloaded from Firebase Console |

---

## 🧠 Gemini Flash Prompt Design

```
System (sent once, cached):
"Reply ONLY in JSON: {message, risk, actions}
 message ≤80 words. Never diagnose. Escalate when unsure."

Per-turn cost: ~100–150 tokens input + ~80 tokens output = ~$0.000035 per check-in
```

---

## 📄 License
MIT — CareLoop Hackathon Project
