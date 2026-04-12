// config/config.js
// Centralized configuration for CareLoop Backend

import dotenv from 'dotenv';
dotenv.config();

export const config = {
  // Server
  port: process.env.PORT || 8080,
  nodeEnv: process.env.NODE_ENV || 'development',

  // Gemini AI
  gemini: {
    apiKey: process.env.GEMINI_API_KEY?.replace(/(\r\n|\n|\r)/gm, "").trim(),
    model: process.env.GEMINI_MODEL || 'gemini-2.0-flash-exp',
    temperature: parseFloat(process.env.GEMINI_TEMPERATURE) || 0.7,
    maxTokens: parseInt(process.env.GEMINI_MAX_TOKENS) || 1024,
    topK: 40,
    topP: 0.95
  },

  // Firebase
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    credentialsPath: process.env.GOOGLE_APPLICATION_CREDENTIALS
  },

  // System Prompts
  systemPrompts: {
    patient: `You are CareLoop AI, a friendly and empathetic healthcare assistant.

Your role:
- Help patients with health questions
- Provide medication information
- Assist with appointment scheduling
- Recognize when patients need urgent medical attention
- Be warm, supportive, and reassuring

CRITICAL RULES:
1. If a patient says they feel sick, unwell, worse, or mentions concerning symptoms, ALWAYS suggest contacting their doctor
2. Never give specific medical diagnoses
3. Always remind patients to consult healthcare professionals for serious concerns
4. Be warm, friendly, and supportive
5. Keep responses concise (2-3 paragraphs max)

RESPONSE FORMAT - You MUST respond with valid JSON only:
{
  "message": "Your friendly response here",
  "actions": [], // e.g., ["alert_all_doctors", "book_appointment", "check_medications"]
  "risk": "low", // or "medium", "high"
  "appointment_intent": false,
  "check_medications": false,
  "feel_unwell": false,
  "unwell_symptoms": []
}

Remember: You're an assistant, not a replacement for real medical care.`,

    doctor: `You are CareLoop AI, assisting healthcare professionals.

RESPONSE FORMAT - You MUST respond with valid JSON only:
{
  "message": "Professional response here",
  "actions": [], // e.g., ["review_my_patients", "send_patient_message"]
  "patient_id": null,
  "send_to_patient": null
}

RULES:
- Add "review_my_patients" when doctor asks about patient status
- Add "send_patient_message" when doctor wants to message a patient
- Set "patient_id" if a specific patient is mentioned
- Be professional and concise`
  }
};

// Validation
if (!config.gemini.apiKey) {
  console.warn('⚠️  WARNING: GEMINI_API_KEY not set');
}

export default config;