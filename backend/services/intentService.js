// services/intentService.js
// Intent analysis service - detects what the user wants to do

/**
 * Chat intent types
 */
export const ChatIntent = {
  CONTACT_DOCTOR: 'contactDoctor',
  BOOK_APPOINTMENT: 'bookAppointment',
  MEDICATION_QUERY: 'medicationQuery',
  GENERAL: 'general',
  SCAN_BILL: 'scanBill'
};

/**
 * Analyze user message and detect intent
 * @param {string} message - User's message
 * @returns {string} - Intent type
 */
export function analyzeIntent(message) {
  const lowerMessage = message.toLowerCase().trim();

  // Emergency/Urgent Contact Doctor patterns
  if (isEmergencyIntent(lowerMessage)) {
    return ChatIntent.CONTACT_DOCTOR;
  }

  // Feeling unwell patterns
  if (isFeelingUnwellIntent(lowerMessage)) {
    return ChatIntent.CONTACT_DOCTOR;
  }

  // Appointment booking patterns
  if (isAppointmentIntent(lowerMessage)) {
    return ChatIntent.BOOK_APPOINTMENT;
  }

  // Medication query patterns
  if (isMedicationIntent('did i take', 'have i taken', 'did i take my', 'took my')) {
    return ChatIntent.MEDICATION_QUERY;
  }

   // Bill scan / analysis patterns
   if (isBillScanIntent(lowerMessage)) {
     return ChatIntent.SCAN_BILL;
   }

  // General health question
  return ChatIntent.GENERAL;
}

/**
 * Check if message indicates emergency or need to contact doctor
 * @param {string} message - Lowercase message
 * @returns {boolean}
 */
function isEmergencyIntent(message) {
  const emergencyKeywords = [
    // Direct requests
    'contact doctor', 'call doctor', 'reach doctor', 'talk to doctor',
    'speak to doctor', 'message doctor', 'get doctor', 'need doctor',
    'see doctor', 'doctor help',

    // Feeling worse/sick
    'feel worse', 'feeling worse', 'getting worse', 'not getting better',
    'feel sick', 'feeling sick', 'feel ill', 'feeling ill',
    'feel terrible', 'feeling terrible', 'feel awful', 'feeling awful',
    'feel bad', 'feeling bad', 'feel unwell', 'feeling unwell',
    'not well', 'very sick', 'really sick',

    // Symptoms worsening
    'pain worse', 'pain increasing', 'more pain', 'severe pain',
    'cant breathe', 'can\'t breathe', 'difficulty breathing',
    'chest pain', 'heart pain', 'bad headache',

    // Emergency words
    'emergency', 'urgent', 'serious', 'critical',

    // Medication not working
    'medicine not working', 'medication not working',
    'not helping', 'still sick', 'still in pain',

    // General distress
    'worried', 'scared', 'concerned', 'afraid',
  ];

  for (const keyword of emergencyKeywords) {
    if (message.includes(keyword)) {
      return true;
    }
  }

  // Check for symptom + severity combinations
  const symptoms = [
    'pain', 'fever', 'cough', 'vomit', 'dizzy', 'weak',
    'nausea', 'bleeding', 'swelling', 'rash'
  ];
  const severityWords = [
    'severe', 'bad', 'terrible', 'worse', 'extreme',
    'intense', 'unbearable', 'serious'
  ];

  for (const symptom of symptoms) {
    for (const severity of severityWords) {
      if (message.includes(symptom) && message.includes(severity)) {
        return true;
      }
    }
  }

  return false;
}

/**
 * Check if message indicates feeling unwell
 * @param {string} message - Lowercase message
 * @returns {boolean}
 */
function isFeelingUnwellIntent(message) {
  const unwellPatterns = [
    'i feel sick', 'im sick', 'i\'m sick', 'feeling sick',
    'i feel bad', 'im not well', 'i\'m not well', 'not feeling good',
    'i feel unwell', 'feeling unwell', 'feeling poorly',
    'something wrong', 'something is wrong', 'not right',
    'worried about', 'concerned about', 'scared',
    'need help', 'help me', 'what should i do',
  ];

  return unwellPatterns.some(pattern => message.includes(pattern));
}

/**
 * Check if message is about booking appointment
 * @param {string} message - Lowercase message
 * @returns {boolean}
 */
function isAppointmentIntent(message) {
  const appointmentKeywords = [
    'book appointment', 'schedule appointment', 'make appointment',
    'book a visit', 'schedule visit', 'see doctor', 'visit doctor',
    'appointment with', 'meet doctor', 'consultation',
    'need appointment', 'want appointment',
  ];

  return appointmentKeywords.some(keyword => message.includes(keyword));
}

/**
 * Check if message is about medication
 * @param {string} message - Lowercase message
 * @returns {boolean}
 */
function isMedicationIntent(message) {
  const medicationKeywords = [
    'medicine', 'medication', 'pill', 'drug', 'dosage',
    'prescription', 'take medicine', 'when to take',
    'my meds', 'my medications', 'what medicines',
  ];

  return medicationKeywords.some(keyword => message.includes(keyword));
}

/**
 * Check if message is about scanning / analysing a bill
 * @param {string} message - Lowercase message
 * @returns {boolean}
 */
function isBillScanIntent(message) {
  const billKeywords = [
    'scan bill', 'scan my bill', 'scan the bill',
    'analyze bill', 'analyse bill', 'analyze my bill', 'analyse my bill',
    'check bill', 'check my bill', 'read my bill',
    'medication bill', 'pharmacy bill', 'medical bill',
    'upload bill', 'send my bill', 'review bill',
    'analyze this bill', 'analyse this bill',
    'analyze receipt', 'analyse receipt',
    'check receipt', 'scan receipt',
    'analyze medication', 'analyse medication',
    'please analyze', 'please analyse',
  ];

  return billKeywords.some(keyword => message.includes(keyword));
}

/**
 * Extract symptoms from message
 * @param {string} message - User's message
 * @returns {Array<string>} - List of detected symptoms
 */
export function extractSymptoms(message) {
  const lowerMessage = message.toLowerCase();
  const symptoms = [];

  const symptomKeywords = {
    'pain': ['pain', 'ache', 'hurt', 'sore'],
    'fever': ['fever', 'temperature', 'hot'],
    'cough': ['cough', 'coughing'],
    'nausea': ['nausea', 'nauseous', 'queasy'],
    'vomiting': ['vomit', 'vomiting', 'throw up'],
    'dizziness': ['dizzy', 'dizziness', 'lightheaded'],
    'weakness': ['weak', 'weakness', 'tired', 'fatigue'],
    'headache': ['headache', 'head pain'],
    'breathing': ['breathe', 'breathing', 'breath'],
    'chest pain': ['chest pain', 'chest hurt']
  };

  for (const [symptom, keywords] of Object.entries(symptomKeywords)) {
    if (keywords.some(keyword => lowerMessage.includes(keyword))) {
      symptoms.push(symptom);
    }
  }

  return symptoms;
}

/**
 * Assess risk level based on message and symptoms
 * @param {string} message - User's message
 * @param {Array<string>} symptoms - Detected symptoms
 * @returns {string} - 'low', 'medium', or 'high'
 */
export function assessRiskLevel(message, symptoms) {
  const lowerMessage = message.toLowerCase();

  // High risk indicators
  const highRiskKeywords = [
    'chest pain', 'can\'t breathe', 'difficulty breathing',
    'severe pain', 'unbearable', 'emergency', 'critical',
    'bleeding heavily', 'passed out', 'unconscious'
  ];

  if (highRiskKeywords.some(keyword => lowerMessage.includes(keyword))) {
    return 'high';
  }

  // Medium risk indicators
  const mediumRiskKeywords = [
    'worse', 'getting worse', 'not better', 'very sick',
    'severe', 'intense', 'terrible', 'awful'
  ];

  if (mediumRiskKeywords.some(keyword => lowerMessage.includes(keyword)) || symptoms.length >= 3) {
    return 'medium';
  }

  // Default to low risk
  return 'low';
}

export default {
  ChatIntent,
  analyzeIntent,
  extractSymptoms,
  assessRiskLevel,
  isBillScanIntent: undefined
};