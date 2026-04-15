// services/enhancedChatService.js
// Enhanced AI Chat Service with full agentic capabilities
import { GoogleGenerativeAI } from '@google/generative-ai';
import { geminiService } from './geminiService.js';
import { firestoreService } from './firestoreService.js';
import { analyzeIntent, ChatIntent, extractSymptoms, assessRiskLevel } from './intentService.js';
import { config } from '../config/config.js';

class EnhancedChatService {
  /**
   * Process patient chat message
   * @param {Object} params - { message, userId, conversationHistory }
   * @returns {Promise<Object>} - AI response with actions
   */
  async processPatientMessage({ message, userId, conversationHistory = [] }) {
    try {
      // Analyze intent
      const intent = analyzeIntent(message);
      console.log(`📊 Intent detected: ${intent}`);

      // Handle based on intent
      switch (intent) {
        case ChatIntent.CONTACT_DOCTOR:
          return await this.handleContactDoctorRequest(userId, message);

        case ChatIntent.BOOK_APPOINTMENT:
          return await this.handleAppointmentRequest(userId, message, conversationHistory);

        case ChatIntent.MEDICATION_QUERY:
          return await this.handleMedicationQuery(userId, message, conversationHistory);

        case ChatIntent.SCAN_BILL:
          return await this.handleScanBillRequest(userId);

        case ChatIntent.GENERAL:
        default:
          return await this.handleGeneralQuery(userId, message, conversationHistory);
      }
    } catch (error) {
      console.error('Error processing patient message:', error);
      throw error;
    }
  }

  /**
   * Process doctor chat message
   * @param {Object} params - { message, doctorId, userContext, conversationHistory }
   * @returns {Promise<Object>} - AI response with actions
   */
  async processDoctorMessage({ message, doctorId, userContext, conversationHistory = [] }) {
      try {
        // Get doctor's patients for context
        let doctorPatients = [];
        try {
          const patients = await firestoreService.getDoctorPatients(doctorId);
          doctorPatients = patients.map(p => ({
            id: p.id,
            name: p.name || 'Unknown Patient',
            diagnosis: p.diagnosis || 'N/A'
          }));
        } catch (err) {
          console.warn('Could not load doctor patients:', err.message);
        }

        // Extract doctor's last name for greeting
        const doctorName = userContext?.name || 'User';
        const doctorLastName = doctorName.split(' ').pop(); // Get last word as last name

        // Build patient summaries
        const patientSummaries = doctorPatients.length > 0
          ? doctorPatients.map(p => `${p.name} (${p.diagnosis})`).join('; ')
          : 'None';

        // Build patient list for selection
        const patientListJson = JSON.stringify(doctorPatients);

        // Build doctor-specific system prompt with context
        const systemPrompt = `${config.systemPrompts.doctor}

  DOCTOR CONTEXT:
  - ID: ${doctorId}
  - Name: Dr. ${doctorName}
  - Last Name: ${doctorLastName}
  - Patient Count: ${doctorPatients.length}
  - Patient Summaries: ${patientSummaries}
  - Available Patients JSON: ${patientListJson}

  IMPORTANT: When responding to queries about patients, checking status, sending messages, or viewing alerts:
  1. Always include the patient_list array in your response with ALL available patients
  2. Greet as "Hello Dr. ${doctorLastName}" not "Hello Dr.User"
  3. Ask doctor to select which patient they want to interact with
  4. Format: patient_list: ${patientListJson}`;

        let response;
        try {
          // Generate response
          response = await geminiService.generateResponse(
            message,
            systemPrompt,
            conversationHistory
          );

          // Ensure patient_list is included for patient-related actions
          const needsPatientList = response.actions?.some(action =>
            ['check_patient_status', 'view_alerts', 'send_patient_message', 'send_appointment_request', 'review_my_patients'].includes(action)
          );

          if (needsPatientList && (!response.patient_list || response.patient_list.length === 0)) {
            response.patient_list = doctorPatients;
          }
        } catch (geminiError) {
          console.error('Gemini doctor response error:', geminiError.message);
          // Return a safe fallback so the doctor always gets a response
          response = {
            message: `I'm here to help, Dr. ${doctorLastName}. Could you clarify your question? I'm ready to assist with patient management, alerts, or medical queries.`,
            actions: [],
            patient_id: null,
            send_to_patient: null,
            patient_list: doctorPatients
          };
        }

        // Log the interaction (non-blocking)
        firestoreService.logChatInteraction({
          userId: doctorId,
          role: 'doctor',
          message,
          response: JSON.stringify(response),
          intent: 'doctor_query',
          risk: 'n/a'
        }).catch(err => console.error('Log error (non-fatal):', err.message));

        return response;
      } catch (error) {
        console.error('Error processing doctor message:', error);
        // Always return a valid response — never let doctor chat 500
        return {
          message: "I'm having a brief technical issue. Please try again in a moment.",
          actions: [],
          patient_id: null,
          send_to_patient: null,
          patient_list: []
        };
      }
    }

  /**
   * Handle contact doctor request - CRITICAL, NO AI INVOLVED
   * @param {string} userId - Patient ID
   * @param {string} message - User's message
   * @returns {Promise<Object>}
   */
  async handleContactDoctorRequest(userId, message) {
    try {
      // Get patient info
      const patient = await firestoreService.getPatient(userId);

      if (!patient) {
        return {
          message: '🚨 I understand you need to contact a doctor. However, I couldn\'t find your profile. Please contact support.',
          actions: [],
          risk: 'high',
          feel_unwell: true
        };
      }

      const assignedDoctorId = patient.assignedDoctorId;

      if (!assignedDoctorId) {
        return {
          message: `🚨 **You Need Medical Attention**

I understand you're not feeling well. Unfortunately, you don't have an assigned doctor yet.

**Please do one of the following:**
- Visit the clinic in person for immediate care
- Call emergency services if it's urgent (999 or 911)
- Contact clinic support to get assigned a doctor

Your health is important. Don't hesitate to seek immediate help if needed.`,
          actions: ['alert_support'],
          risk: 'high',
          feel_unwell: true,
          unwell_symptoms: extractSymptoms(message)
        };
      }

      // Get doctor info
      const doctor = await firestoreService.getDoctor(assignedDoctorId);

      if (!doctor) {
        return {
          message: '🚨 I understand you need to contact a doctor, but there was an error. Please contact clinic support immediately.',
          actions: ['alert_support'],
          risk: 'high',
          feel_unwell: true
        };
      }

      const doctorName = doctor.name || 'your doctor';

      // Extract symptoms and assess risk
      const symptoms = extractSymptoms(message);
      const risk = assessRiskLevel(message, symptoms);

      // Send urgent message to doctor
      await firestoreService.sendUrgentMessage({
        patientId: userId,
        patientName: patient.name || 'Patient',
        doctorId: assignedDoctorId,
        doctorName: doctorName,
        message: message,
        riskLevel: risk
      });

      // Update patient risk level
      await firestoreService.updatePatientRiskLevel(userId, risk);

      // Log the interaction
      await firestoreService.logChatInteraction({
        userId,
        role: 'patient',
        message,
        response: 'urgent_doctor_contact',
        intent: ChatIntent.CONTACT_DOCTOR,
        risk
      });

      return {
        message: `🚨 **Urgent Message Sent to Dr. ${doctorName}**

I've immediately notified Dr. ${doctorName} about your condition. They will be alerted and should respond shortly.

**While you wait:**
- If this is a medical emergency, call 999 or 911 immediately
- Continue taking prescribed medications as scheduled
- Rest and stay hydrated
- Monitor your symptoms and note any changes

**Dr. ${doctorName} has been alerted and will contact you soon.**

If you don't hear back within 30 minutes and your symptoms worsen, please go to the nearest emergency room or call emergency services.`,
        actions: ['alert_all_doctors'],
        risk,
        feel_unwell: true,
        unwell_symptoms: symptoms
      };

    } catch (error) {
      console.error('Error handling contact doctor request:', error);

      return {
        message: `🚨 **Technical Error**

I understand you need to contact a doctor urgently. There was a technical error sending the message.

**Please:**
- Call the clinic directly immediately
- Visit in person if urgent
- Call emergency services (999 or 911) if it's an emergency

Don't wait - your health is the priority.`,
        actions: ['alert_support'],
        risk: 'high',
        feel_unwell: true,
        error: error.message
      };
    }
  }

  /**
   * Handle appointment request with AI
   * @param {string} userId - Patient ID
   * @param {string} message - User's message
   * @param {Array} history - Conversation history
   * @returns {Promise<Object>}
   */
  async handleAppointmentRequest(userId, message, history) {
    try {
      // Build context-aware prompt
      const systemPrompt = `${config.systemPrompts.patient}

The patient wants to book an appointment. Their message: "${message}"

Provide a helpful response that:
1. Acknowledges their request
2. Asks what type of appointment they need (checkup, follow-up, specific concern)
3. Offers to help them schedule it
4. Be friendly and efficient

Keep it concise and actionable.`;

      // Generate AI response
      const response = await geminiService.generateResponse(
        message,
        systemPrompt,
        history
      );

      // Ensure appointment_intent is set
      if (!response.appointment_intent) {
        response.appointment_intent = true;
      }

      // Ensure actions include book_appointment
      if (!response.actions) {
        response.actions = [];
      }
      if (!response.actions.includes('book_appointment')) {
        response.actions.push('book_appointment');
      }

      // Log the interaction
      await firestoreService.logChatInteraction({
        userId,
        role: 'patient',
        message,
        response: JSON.stringify(response),
        intent: ChatIntent.BOOK_APPOINTMENT,
        risk: response.risk || 'low'
      });

      return response;

    } catch (error) {
      console.error('Error handling appointment request:', error);

      return {
        message: `📅 **Let me help you book an appointment!**

Please tell me:
1. What type of appointment do you need?
2. Is it for a specific health concern or a general checkup?
3. When would you prefer to come in?

I'll help you find the best available time!`,
        actions: ['book_appointment'],
        appointment_intent: true,
        risk: 'low'
      };
    }
  }

  /**
   * Handle medication query with AI and patient data
   * @param {string} userId - Patient ID
   * @param {string} message - User's message
   * @param {Array} history - Conversation history
   * @returns {Promise<Object>}
   */
  async handleMedicationQuery(userId, message, history) {
    try {
      // Get patient medications (with subcollection + top-level fallback)
      const medications = await (firestoreService.getPatientMedicationsWithFallback
        ? firestoreService.getPatientMedicationsWithFallback(userId)
        : firestoreService.getPatientMedications(userId));

      if (medications.length === 0) {
        return {
          message: `💊 You don't have any prescribed medications in our system currently.

If you think you should have medications listed, please:
- Contact your doctor
- Visit the clinic
- Check with our support team

Is there anything else I can help you with?`,
          actions: [],
          check_medications: true,
          risk: 'low'
        };
      }

      // Format medication list
      const medList = medications.map(med => {
        const name = med.name || 'Unknown';
        const dosage = med.dosage || '';
        const times = Array.isArray(med.times) ? med.times.join(', ') : '';
        return `• ${name} ${dosage} (Times: ${times})`;
      }).join('\n');

      // Build context-aware prompt
      const systemPrompt = `${config.systemPrompts.patient}

The patient has these medications:
${medList}

Their question: "${message}"

Provide helpful information about their medications. Include:
1. Answer their specific question
2. General medication reminders (take on time, don't skip doses)
3. Suggest contacting doctor if they have concerns about side effects

Be concise and helpful.`;

      // Generate AI response
      const response = await geminiService.generateResponse(
        message,
        systemPrompt,
        history
      );

      // Ensure check_medications is set
      if (!response.check_medications) {
        response.check_medications = true;
      }

      // Log the interaction
      await firestoreService.logChatInteraction({
        userId,
        role: 'patient',
        message,
        response: JSON.stringify(response),
        intent: ChatIntent.MEDICATION_QUERY,
        risk: response.risk || 'low'
      });

      return response;

    } catch (error) {
      console.error('Error handling medication query:', error);

      return {
        message: '💊 I had trouble accessing your medication information. Please try again or contact support.',
        actions: [],
        check_medications: true,
        risk: 'low',
        error: error.message
      };
    }
  }

  /**
   * Handle bill scan request — prompt user to upload an image
   * @param {string} userId - Patient ID
   * @returns {Object}
   */
  async handleScanBillRequest(userId) {
    // Log the interaction (non-blocking)
    firestoreService.logChatInteraction({
      userId,
      role: 'patient',
      message: 'scan_bill_request',
      response: 'prompt_to_upload',
      intent: 'scanBill',
      risk: 'low'
    }).catch(() => {});

    return {
      message: `Sure! Send me your bill! 📸\n\nTap the 📎 **attachment icon** at the bottom of the chat to upload a photo of your medication bill or pharmacy receipt.\n\nI'll:\n✅ Extract all items and prices\n✅ Check for overcharges or errors\n✅ Give you a clear patient-friendly summary\n✅ Suggest potential savings\n\nMake sure the photo is clear and well-lit for the best results!`,
      actions: ['open_image_picker'],
      risk: 'low',
      appointment_intent: false,
      check_medications: false,
      feel_unwell: false,
      unwell_symptoms: []
    };
  }

  /**
   * Handle general query with AI
   * @param {string} userId - Patient ID
   * @param {string} message - User's message
   * @param {Array} history - Conversation history
   * @returns {Promise<Object>}
   */
  async handleGeneralQuery(userId, message, history) {
    try {
      // Generate AI response
      const response = await geminiService.generateResponse(
        message,
        config.systemPrompts.patient,
        history
      );

      // Extract symptoms and assess risk from the message
      const symptoms = extractSymptoms(message);
      const risk = assessRiskLevel(message, symptoms);

      // Override risk if AI detected something concerning
      if (response.risk && response.risk !== 'low') {
        response.risk = response.risk;
      } else if (risk !== 'low') {
        response.risk = risk;
      }

      // Add symptoms if detected
      if (symptoms.length > 0 && !response.unwell_symptoms) {
        response.unwell_symptoms = symptoms;
      }

      // Check if patient is feeling unwell - send notification to doctor
      if (response.feel_unwell || symptoms.length > 0 || risk !== 'low') {
        response.feel_unwell = true;

        // Get patient info and send notification to doctor
        try {
          const patient = await firestoreService.getPatient(userId);
          if (patient && patient.assignedDoctorId) {
            await firestoreService.sendUrgentMessage({
              patientId: userId,
              patientName: patient.name || 'Patient',
              doctorId: patient.assignedDoctorId,
              doctorName: 'Doctor',
              message: message,
              riskLevel: response.risk || risk
            });
            console.log('🚨 Urgent notification sent to doctor for patient feeling unwell');
          }
        } catch (notifError) {
          console.error('⚠️ Failed to send doctor notification (non-fatal):', notifError.message);
        }
      }

      // Log the interaction
      await firestoreService.logChatInteraction({
        userId,
        role: 'patient',
        message,
        response: JSON.stringify(response),
        intent: ChatIntent.GENERAL,
        risk: response.risk || 'low'
      });

      return response;

    } catch (error) {
      console.error('Error handling general query:', error);

      return {
        message: `I'm here to help! I can assist you with:

📅 **Booking appointments** - Just ask to book an appointment
💊 **Medication info** - Ask about your medicines
👨‍⚕️ **Contact your doctor** - Tell me if you're not feeling well
🏥 **Health questions** - Ask me anything about your health

What would you like help with?`,
        actions: [],
        risk: 'low'
      };
    }
  }
}

// Export singleton instance
export const enhancedChatService = new EnhancedChatService();
export default enhancedChatService;