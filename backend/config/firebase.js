import fs from "fs";
import admin from "firebase-admin";
import { config } from "./config.js";

let firebaseInitialized = false;

export function initializeFirebase() {
  if (firebaseInitialized) return admin;

  try {
    console.log("🔥 Initializing Firebase...");

    if (config.firebase.credentialsPath) {
      const serviceAccount = JSON.parse(
        fs.readFileSync(config.firebase.credentialsPath, "utf8")
      );

      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });

      console.log("✅ Firebase initialized with service account file");
    }

    else if (
      config.firebase.projectId &&
      config.firebase.privateKey &&
      config.firebase.clientEmail
    ) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: config.firebase.projectId,
          clientEmail: config.firebase.clientEmail,
          privateKey: config.firebase.privateKey,
        }),
      });

      console.log("✅ Firebase initialized with environment variables");
    }

    else {
      admin.initializeApp();
      console.log("✅ Firebase initialized with default credentials");
    }

    firebaseInitialized = true;
    return admin;

  } catch (error) {
    console.error("❌ Firebase initialization error:", error);
    throw error;
  }
}

export function getFirestore() {
  if (!firebaseInitialized) initializeFirebase();
  return admin.firestore();
}

export function getFieldValue() {
  if (!firebaseInitialized) initializeFirebase();
  return admin.firestore.FieldValue;
}

export default {
  initializeFirebase,
  getFirestore,
  getFieldValue,
};