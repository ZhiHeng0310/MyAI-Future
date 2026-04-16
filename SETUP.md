# CareLoop Setup Guide

## Prerequisites

Install the following before starting:

- **Flutter SDK** `>=3.2.0 <4.0.0`
- **Dart SDK** (comes with Flutter)
- **Node.js** `18+`
- **Google Cloud CLI** *(optional, for Cloud Run deployment)*
- Android Studio / VS Code with Flutter extensions

---

## 1. Clone the Repository

```bash
git clone https://github.com/ZhiHeng0310/MyAI-Future.git
cd MyAI-Future
```

---

## 2. Install Frontend Dependencies

```bash
flutter pub get
```

---

## 3. Install Backend Dependencies

```bash
cd backend
npm install
cd ..
```

---

## 4. Configure Firebase (Auth + Firestore) & Backend Secrets

This project uses Firebase for Authentication and Firestore.

### Create Firebase Project

1. Go to Firebase Console
2. Create a new project
3. Enable:
   - Authentication
   - Firestore Database

### Generate Firebase Config

Run:

```bash
flutterfire configure
```

This updates:

- `lib/firebase_options.dart`

### Backend Setup (Cloud Run)

Generate a service account key:

- Firebase Console → Project Settings → Service Accounts
- Download private key JSON

Add it to Cloud Run environment variable:

FIREBASE\_SERVICE\_ACCOUNT

---

## 5. Configure Frontend Environment Variables

This project loads environment variables using flutter_dotenv, so the .env file must be placed inside the assets/ folder.

Create:
```
assets/.env
```

```env
API_BASE_URL=https://your-backend-url.run.app
GEMINI_KEY=your_gemini_api_key
GEMINI_MODEL=gemma-3-27b-it
DEFAULT_CLINIC_ID=clinic_main
```
Then register it in pubspec.yaml:
```
flutter:
  assets:
    - assets/.env
```
Without adding the .env file to Flutter assets, flutter_dotenv will fail to load it at runtime.

---

## 6. Configure Backend Environment Variables

Create `backend/.env`:

```env
NODE_ENV=development
PORT=8080
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemma-3-27b-it
GEMINI_TEMPERATURE=0.7
GEMINI_MAX_TOKENS=2048

# Firebase Admin (Option A)
FIREBASE_SERVICE_ACCOUNT={JSON_STRINGIFIED_SERVICE_ACCOUNT}

# OR Firebase Admin (Option B)
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_CLIENT_EMAIL=your_client_email
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

> Use either `FIREBASE_SERVICE_ACCOUNT` **or** the individual Firebase credential fields.

---

## 7. Run Backend Locally

```bash
cd backend
npm run dev
```

Backend default URL:

```text
http://localhost:8080
```

If running locally, update frontend `.env`:

```env
API_BASE_URL=http://localhost:8080
```

---

## 8. Run Flutter App (🧑 For Users (Using the App))

```bash
flutter run
```

Optional: Run with environment variables

---

## 9. Build for Production

### Flutter Web

```bash
flutter build web
```

---

## 10. Deploy Backend to Google Cloud Run (👨‍💻 For Developers (Self-hosting / Deployment))

From project root:

```bash
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/careloop-backend ./backend
```

```bash
gcloud run deploy careloop-backend \
  --image gcr.io/YOUR_PROJECT_ID/careloop-backend \
  --platform managed \
  --region asia-southeast1 \
  --allow-unauthenticated \
  --set-env-vars="NODE_ENV=production,GEMINI_MODEL=gemma-3-27b-it"
```

Alternative way(CI/CD - GitHub Actions):

Backend deployment is automated via GitHub Actions on push to main.
This project uses GitHub Actions to deploy backend to Google Cloud Run automatically.
Push to main branch will trigger deployment.

Do NOT modify `.github/workflows/deploy.yml` unless you are changing deployment setup.

### Required:
- Google Cloud Project
- GitHub Secrets configuration
- Firebase project setup

---

## 11. Deploy Flutter Web to Cloud Run (👨‍💻 For Developers (Self-hosting / Deployment))

```bash
flutter build web

gcloud run deploy careloop-frontend \
  --source build/web \
  --region asia-southeast1 \
  --allow-unauthenticated
```
⚠️ Simple deployment method only.
Recommended production approach:
- Google Cloud Storage + CDN (best performance)
- or Firebase Hosting (optional)

---

⚠️ Security Notice
Do not commit:
- .env files
- Firebase service account JSON
- API keys

## Troubleshooting

### Firebase Auth 400 Errors

- Confirm Firebase Auth provider is enabled
- Verify `firebase_options.dart` matches your Firebase project

### Backend 500 Errors

- Check `backend/.env` values
- Confirm Firebase Admin credentials are valid

### API Connection Failed

- Verify `API_BASE_URL` points to active backend
- Ensure backend CORS allows frontend origin

---

## Project Structure

```text
/lib        -> Flutter frontend
/backend    -> Express + Gemini AI backend
/web        -> Flutter web assets
```

