// lib/services/enhanced_ai_chat_service_gemini.dart
// Enhanced AI Chat Service with Gemini AI Integration

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'gemini_ai_service.dart';

class EnhancedAIChatService {
  static final EnhancedAIChatService _instance = EnhancedAIChatService._();
  static EnhancedAIChatService get instance => _instance;
  EnhancedAIChatService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeminiAIService _gemini = GeminiAIService.instance;

  // System prompt to guide Gemini's behavior
  static const String _systemPrompt = '''
You are a helpful medical assistant AI for CareLoop, a healthcare management app.

Your role:
- Help patients with health questions
- Provide medication information
- Assist with appointment scheduling
- Recognize when patients need urgent medical attention
- Be empathetic and reassuring

IMPORTANT RULES:
1. If a patient says they feel sick, unwell, worse, or mentions concerning symptoms, ALWAYS suggest contacting their doctor
2. Never give specific medical diagnoses
3. Always remind patients to consult healthcare professionals for serious concerns
4. Be warm, friendly, and supportive
5. Keep responses concise (2-3 paragraphs max)

Remember: You're an assistant, not a replacement for real medical care.
''';

  /// Analyze user message and detect intent
  ChatIntent analyzeIntent(String message) {
    final lowerMessage = message.toLowerCase().trim();

    // Emergency/Urgent Contact Doctor patterns
    if (_isEmergencyIntent(lowerMessage)) {
      return ChatIntent.contactDoctor;
    }

    // Feeling unwell patterns
    if (_isFeelingUnwellIntent(lowerMessage)) {
      return ChatIntent.contactDoctor;
    }

    // Appointment booking patterns
    if (_isAppointmentIntent(lowerMessage)) {
      return ChatIntent.bookAppointment;
    }

    // Medication query patterns
    if (_isMedicationIntent(lowerMessage)) {
      return ChatIntent.medicationQuery;
    }

    // General health question
    return ChatIntent.general;
  }

  /// Check if message indicates emergency or need to contact doctor
  bool _isEmergencyIntent(String message) {
    final emergencyKeywords = [
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

    for (var keyword in emergencyKeywords) {
      if (message.contains(keyword)) {
        return true;
      }
    }

    // Check for symptom + severity combinations
    final symptoms = ['pain', 'fever', 'cough', 'vomit', 'dizzy', 'weak',
      'nausea', 'bleeding', 'swelling', 'rash'];
    final severityWords = ['severe', 'bad', 'terrible', 'worse', 'extreme',
      'intense', 'unbearable', 'serious'];

    for (var symptom in symptoms) {
      for (var severity in severityWords) {
        if (message.contains(symptom) && message.contains(severity)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Check if message indicates feeling unwell (should contact doctor)
  bool _isFeelingUnwellIntent(String message) {
    final unwellPatterns = [
      'i feel sick', 'im sick', 'i\'m sick', 'feeling sick',
      'i feel bad', 'im not well', 'i\'m not well', 'not feeling good',
      'i feel unwell', 'feeling unwell', 'feeling poorly',
      'something wrong', 'something is wrong', 'not right',
      'worried about', 'concerned about', 'scared',
      'need help', 'help me', 'what should i do',
    ];

    for (var pattern in unwellPatterns) {
      if (message.contains(pattern)) {
        return true;
      }
    }

    return false;
  }

  /// Check if message is about booking appointment
  bool _isAppointmentIntent(String message) {
    final appointmentKeywords = [
      'book appointment', 'schedule appointment', 'make appointment',
      'book a visit', 'schedule visit', 'see doctor', 'visit doctor',
      'appointment with', 'meet doctor', 'consultation',
      'need appointment', 'want appointment',
    ];

    return appointmentKeywords.any((keyword) => message.contains(keyword));
  }

  /// Check if message is about medication
  bool _isMedicationIntent(String message) {
    final medicationKeywords = [
      'medicine', 'medication', 'pill', 'drug', 'dosage',
      'prescription', 'take medicine', 'when to take',
      'my meds', 'my medications', 'what medicines',
    ];

    return medicationKeywords.any((keyword) => message.contains(keyword));
  }

  /// Generate AI response using Gemini with intent awareness
  Future<String> generateResponse({
    required String message,
    required String userId,
    required ChatIntent intent,
    List<ChatMessage>? conversationHistory,
  }) async {
    // Handle special intents first (these bypass Gemini for critical functions)
    switch (intent) {
      case ChatIntent.contactDoctor:
        return await _handleContactDoctorRequest(userId, message);

      case ChatIntent.bookAppointment:
        return await _handleAppointmentRequestWithGemini(userId, message, conversationHistory);

      case ChatIntent.medicationQuery:
        return await _handleMedicationQueryWithGemini(userId, message, conversationHistory);

      case ChatIntent.general:
        return await _handleGeneralQueryWithGemini(message, conversationHistory);
    }
  }

  /// Handle contact doctor request (CRITICAL - NO AI INVOLVED)
  Future<String> _handleContactDoctorRequest(
      String userId,
      String message,
      ) async {
    try {
      // Get patient info
      final patientDoc = await _firestore
          .collection('patients')
          .doc(userId)
          .get();

      if (!patientDoc.exists) {
        return '🚨 I understand you need to contact a doctor. However, I couldn\'t find your profile. Please contact support.';
      }

      final patientData = patientDoc.data()!;
      final assignedDoctorId = patientData['assignedDoctorId'] as String?;

      if (assignedDoctorId == null) {
        return '🚨 **You Need Medical Attention**\n\n'
            'I understand you\'re not feeling well. Unfortunately, you don\'t have an assigned doctor yet.\n\n'
            '**Please do one of the following:**\n'
            '• Visit the clinic in person for immediate care\n'
            '• Call emergency services if it\'s urgent (999 or 911)\n'
            '• Contact clinic support to get assigned a doctor\n\n'
            'Your health is important. Don\'t hesitate to seek immediate help if needed.';
      }

      // Get doctor info
      final doctorDoc = await _firestore
          .collection('doctors')
          .doc(assignedDoctorId)
          .get();

      if (!doctorDoc.exists) {
        return '🚨 I understand you need to contact a doctor, but there was an error. Please contact clinic support immediately.';
      }

      final doctorData = doctorDoc.data()!;
      final doctorName = doctorData['name'] ?? 'your doctor';

      // Create urgent message to doctor
      await _firestore
          .collection('urgent_messages')
          .add({
        'patientId': userId,
        'patientName': patientData['name'] ?? 'Patient',
        'doctorId': assignedDoctorId,
        'doctorName': doctorName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'priority': 'urgent',
      });

      // Notify doctor
      await _firestore
          .collection('doctor_inbox')
          .doc(assignedDoctorId)
          .collection('messages')
          .add({
        'title': '🚨 Urgent: Patient Needs Attention',
        'message': '${patientData['name']} reports: "$message"',
        'patientId': userId,
        'patientName': patientData['name'],
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // ✅ ADDITIONAL: Also create a health_alert entry for doctor's alert screen
      await _firestore
          .collection('health_alerts')
          .add({
        'patientId': userId,
        'patientName': patientData['name'],
        'doctorId': assignedDoctorId,
        'doctorName': doctorName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'riskLevel': 'high',
        'status': 'pending',
        'symptoms': [],
        'type': 'patient_unwell',
      });

      debugPrint('✅ Health alert also created in health_alerts collection');

      debugPrint('✅ FIX 2: Health alert notification created for doctor $assignedDoctorId');

      return '🚨 **Urgent Message Sent to Dr. $doctorName**\n\n'
          'I\'ve immediately notified Dr. $doctorName about your condition. '
          'They will be alerted and should respond shortly.\n\n'
          '**While you wait:**\n'
          '• If this is a medical emergency, call 999 or 911 immediately\n'
          '• Continue taking prescribed medications as scheduled\n'
          '• Rest and stay hydrated\n'
          '• Monitor your symptoms and note any changes\n\n'
          '**Dr. $doctorName has been alerted and will contact you soon.**\n\n'
          'If you don\'t hear back within 30 minutes and your symptoms worsen, '
          'please go to the nearest emergency room or call emergency services.';

    } catch (e) {
      debugPrint('Error handling contact doctor request: $e');
      return '🚨 **Technical Error**\n\n'
          'I understand you need to contact a doctor urgently. There was a technical error sending the message.\n\n'
          '**Please:**\n'
          '• Call the clinic directly immediately\n'
          '• Visit in person if urgent\n'
          '• Call emergency services (999 or 911) if it\'s an emergency\n\n'
          'Don\'t wait - your health is the priority.';
    }
  }

  /// Handle appointment request with Gemini AI
  Future<String> _handleAppointmentRequestWithGemini(
      String userId,
      String message,
      List<ChatMessage>? history,
      ) async {
    final prompt = '''
$_systemPrompt

The patient wants to book an appointment. Their message: "$message"

Provide a helpful response that:
1. Acknowledges their request
2. Asks what type of appointment they need (checkup, follow-up, specific concern)
3. Offers to help them schedule it
4. Be friendly and efficient

Keep it concise and actionable.
''';

    try {
      if (history != null && history.isNotEmpty) {
        return await _gemini.generateResponseWithHistory(
          userMessage: prompt,
          history: history,
        );
      } else {
        return await _gemini.generateResponse(prompt);
      }
    } catch (e) {
      debugPrint('Gemini error: $e');
      return '📅 **Let me help you book an appointment!**\n\n'
          'Please tell me:\n'
          '1. What type of appointment do you need?\n'
          '2. Is it for a specific health concern or a general checkup?\n'
          '3. When would you prefer to come in?\n\n'
          'I\'ll help you find the best available time!';
    }
  }

  /// Handle medication query with Gemini AI
  Future<String> _handleMedicationQueryWithGemini(
      String userId,
      String message,
      List<ChatMessage>? history,
      ) async {
    try {
      // Get patient medications from Firestore
      final medications = await _firestore
          .collection('patients')
          .doc(userId)
          .collection('medications')
          .get();

      if (medications.docs.isEmpty) {
        return '💊 You don\'t have any prescribed medications in our system currently.\n\n'
            'If you think you should have medications listed, please:\n'
            '• Contact your doctor\n'
            '• Visit the clinic\n'
            '• Check with our support team\n\n'
            'Is there anything else I can help you with?';
      }

      String medList = '';
      for (var doc in medications.docs) {
        final data = doc.data();
        final name = data['name'] ?? 'Unknown';
        final dosage = data['dosage'] ?? '';
        final times = (data['times'] as List<dynamic>?)?.join(', ') ?? '';
        medList += '• $name $dosage (Times: $times)\n';
      }

      final prompt = '''
$_systemPrompt

The patient has these medications: 
$medList

Their question: "$message"

Provide helpful information about their medications. Include:
1. Answer their specific question
2. General medication reminders (take on time, don't skip doses)
3. Suggest contacting doctor if they have concerns about side effects

Be concise and helpful.
''';

      if (history != null && history.isNotEmpty) {
        return await _gemini.generateResponseWithHistory(
          userMessage: prompt,
          history: history,
        );
      } else {
        return await _gemini.generateResponse(prompt);
      }
    } catch (e) {
      debugPrint('Medication query error: $e');
      return '💊 I had trouble accessing your medication information. Please try again or contact support.';
    }
  }

  /// Handle general query with Gemini AI
  Future<String> _handleGeneralQueryWithGemini(
      String message,
      List<ChatMessage>? history,
      ) async {
    final prompt = '''
$_systemPrompt

Patient message: "$message"

Provide a helpful, empathetic response. If they mention any health concerns, gently suggest they contact their doctor.

Keep the response friendly, concise (2-3 paragraphs max), and actionable.
''';

    try {
      if (history != null && history.isNotEmpty) {
        return await _gemini.generateResponseWithHistory(
          userMessage: prompt,
          history: history,
        );
      } else {
        return await _gemini.generateResponse(prompt);
      }
    } catch (e) {
      debugPrint('Gemini error: $e');
      return 'I\'m here to help! I can assist you with:\n\n'
          '📅 **Booking appointments** - Just ask to book an appointment\n'
          '💊 **Medication info** - Ask about your medicines\n'
          '👨‍⚕️ **Contact your doctor** - Tell me if you\'re not feeling well\n'
          '🏥 **Health questions** - Ask me anything about your health\n\n'
          'What would you like help with?';
    }
  }
}

enum ChatIntent {
  contactDoctor,
  bookAppointment,
  medicationQuery,
  general,
}