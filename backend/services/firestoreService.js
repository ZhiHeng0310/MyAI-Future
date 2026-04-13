// services/firestoreService.js
// Firestore service for all database operations

import { getFirestore, getFieldValue } from '../config/firebase.js';

class FirestoreService {
  constructor() {
    this.db = null;
    this.FieldValue = null;
  }

  /**
   * Initialize Firestore
   */
  initialize() {
    if (!this.db) {
      this.db = getFirestore();
      this.FieldValue = getFieldValue();
    }
  }

  /**
   * Get patient data
   * @param {string} userId - Patient ID
   * @returns {Promise<Object|null>}
   */
  async getPatient(userId) {
    this.initialize();

    try {
      const patientDoc = await this.db.collection('patients').doc(userId).get();

      if (!patientDoc.exists) {
        return null;
      }

      return {
        id: patientDoc.id,
        ...patientDoc.data()
      };
    } catch (error) {
      console.error('Error getting patient:', error);
      throw error;
    }
  }

  /**
   * Get doctor data
   * @param {string} doctorId - Doctor ID
   * @returns {Promise<Object|null>}
   */
  async getDoctor(doctorId) {
    this.initialize();

    try {
      const doctorDoc = await this.db.collection('doctors').doc(doctorId).get();

      if (!doctorDoc.exists) {
        return null;
      }

      return {
        id: doctorDoc.id,
        ...doctorDoc.data()
      };
    } catch (error) {
      console.error('Error getting doctor:', error);
      throw error;
    }
  }

  /**
   * Get patient medications
   * @param {string} userId - Patient ID
   * @returns {Promise<Array>}
   */
  async getPatientMedications(userId) {
    this.initialize();

    try {
      const medicationsSnapshot = await this.db
        .collection('patients')
        .doc(userId)
        .collection('medications')
        .get();

      const medications = [];
      medicationsSnapshot.forEach(doc => {
        medications.push({
          id: doc.id,
          ...doc.data()
        });
      });

      return medications;
    } catch (error) {
      console.error('Error getting medications:', error);
      throw error;
    }
  }

  /**
   * Send urgent message to doctor
   * @param {Object} data - Message data
   * @returns {Promise<string>} - Message ID
   */
  async sendUrgentMessage(data) {
    this.initialize();

    try {
      const { patientId, patientName, doctorId, doctorName, message } = data;

      // Create urgent message
      const urgentMessageRef = await this.db.collection('urgent_messages').add({
        patientId,
        patientName,
        doctorId,
        doctorName,
        message,
        timestamp: this.FieldValue.serverTimestamp(),
        status: 'pending',
        priority: 'urgent'
      });

      // Notify doctor in inbox
      await this.db
        .collection('doctor_inbox')
        .doc(doctorId)
        .collection('messages')
        .add({
          title: '🚨 Urgent: Patient Needs Attention',
          message: `${patientName} reports: "${message}"`,
          patientId,
          patientName,
          timestamp: this.FieldValue.serverTimestamp(),
          isRead: false
        });

      return urgentMessageRef.id;
    } catch (error) {
      console.error('Error sending urgent message:', error);
      throw error;
    }
  }

  /**
   * Create appointment request
   * @param {Object} data - Appointment data
   * @returns {Promise<string>} - Appointment ID
   */
  async createAppointmentRequest(data) {
    this.initialize();

    try {
      const appointmentRef = await this.db.collection('appointment_requests').add({
        ...data,
        timestamp: this.FieldValue.serverTimestamp(),
        status: 'pending'
      });

      return appointmentRef.id;
    } catch (error) {
      console.error('Error creating appointment:', error);
      throw error;
    }
  }

  /**
   * Log chat interaction
   * @param {Object} data - Chat log data
   * @returns {Promise<string>} - Log ID
   */
  async logChatInteraction(data) {
    this.initialize();

    try {
      const { userId, role, message, response, intent, risk } = data;

      const logRef = await this.db.collection('chat_logs').add({
        userId,
        role,
        message,
        response,
        intent,
        risk,
        timestamp: this.FieldValue.serverTimestamp()
      });

      return logRef.id;
    } catch (error) {
      console.error('Error logging chat:', error);
      // Don't throw - logging failure shouldn't break the app
      return null;
    }
  }

  /**
   * Get patient summaries for doctor
   * @param {string} doctorId - Doctor ID
   * @returns {Promise<Array>}
   */
  async getPatientSummariesForDoctor(doctorId) {
    this.initialize();

    try {
      const patientsSnapshot = await this.db
        .collection('patients')
        .where('assignedDoctorId', '==', doctorId)
        .get();

      const summaries = [];
      patientsSnapshot.forEach(doc => {
        const data = doc.data();
        summaries.push({
          id: doc.id,
          name: data.name,
          diagnosis: data.diagnosis,
          lastCheckIn: data.lastCheckIn,
          riskLevel: data.riskLevel || 'low'
        });
      });

      return summaries;
    } catch (error) {
      console.error('Error getting patient summaries:', error);
      throw error;
    }
  }

  /**
   * Update patient risk level
   * @param {string} userId - Patient ID
   * @param {string} risk - Risk level
   * @returns {Promise<void>}
   */
  async updatePatientRiskLevel(userId, risk) {
    this.initialize();

    try {
      await this.db.collection('patients').doc(userId).update({
        riskLevel: risk,
        lastRiskUpdate: this.FieldValue.serverTimestamp()
      });
    } catch (error) {
      console.error('Error updating risk level:', error);
      // Don't throw - this is a non-critical update
    }
  }

  /**
   * Get all doctors (used when patient has no assigned doctor)
   * @returns {Promise<Array>}
   */
  async getAllDoctors() {
    this.initialize();

    try {
      const snapshot = await this.db.collection('doctors').limit(20).get();
      const doctors = [];
      snapshot.forEach(doc => {
        doctors.push({ id: doc.id, ...doc.data() });
      });
      return doctors;
    } catch (error) {
      console.error('Error getting all doctors:', error);
      return [];
    }
  }

  /**
   * Get top-level medications collection for a patient
   * Also checks the subcollection path as a fallback
   * @param {string} userId - Patient ID
   * @returns {Promise<Array>}
   */
  async getPatientMedicationsWithFallback(userId) {
    this.initialize();

    try {
      // Primary: subcollection under patient document
      const subSnap = await this.db
        .collection('patients').doc(userId)
        .collection('medications').get();

      if (!subSnap.empty) {
        const meds = [];
        subSnap.forEach(doc => meds.push({ id: doc.id, ...doc.data() }));
        return meds;
      }

      // Fallback: top-level medications collection filtered by patientId
      const topSnap = await this.db
        .collection('medications')
        .where('patientId', '==', userId)
        .get();

      const meds = [];
      topSnap.forEach(doc => meds.push({ id: doc.id, ...doc.data() }));
      return meds;
    } catch (error) {
      console.error('Error getting medications (with fallback):', error);
      return [];
    }
  }
}

// Export singleton instance
export const firestoreService = new FirestoreService();
export default firestoreService;