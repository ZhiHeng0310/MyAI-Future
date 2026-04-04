import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class EnhancedAIChatService {
  static final EnhancedAIChatService _instance = EnhancedAIChatService._();
  static EnhancedAIChatService get instance => _instance;
  EnhancedAIChatService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      // Feeling worse/sick
      'feel worse', 'feeling worse', 'getting worse', 'not getting better',
      'feel sick', 'feeling sick', 'feel ill', 'feeling ill',
      'feel terrible', 'feeling terrible', 'feel awful', 'feeling awful',
      'feel bad', 'feeling bad', 'feel unwell', 'feeling unwell',

      // Symptoms worsening
      'pain worse', 'pain increasing', 'more pain', 'severe pain',
      'cant breathe', 'can\'t breathe', 'difficulty breathing',
      'chest pain', 'heart pain',

      // Emergency words
      'emergency', 'urgent', 'help', 'serious', 'critical',

      // Medication not working
      'medicine not working', 'medication not working',
      'not helping', 'still sick', 'still in pain',
    ];

    for (var keyword in emergencyKeywords) {
      if (message.contains(keyword)) {
        return true;
      }
    }

    // Check for symptom + severity combinations
    final symptoms = ['pain', 'fever', 'cough', 'vomit', 'dizzy', 'weak'];
    final severityWords = ['severe', 'bad', 'terrible', 'worse', 'extreme'];

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
    ];

    return appointmentKeywords.any((keyword) => message.contains(keyword));
  }

  /// Check if message is about medication
  bool _isMedicationIntent(String message) {
    final medicationKeywords = [
      'medicine', 'medication', 'pill', 'drug', 'dosage',
      'prescription', 'take medicine', 'when to take',
    ];

    return medicationKeywords.any((keyword) => message.contains(keyword));
  }

  /// Generate appropriate AI response based on intent
  Future<String> generateResponse({
    required String message,
    required String userId,
    required ChatIntent intent,
  }) async {
    switch (intent) {
      case ChatIntent.contactDoctor:
        return await _handleContactDoctorRequest(userId, message);

      case ChatIntent.bookAppointment:
        return _handleAppointmentRequest();

      case ChatIntent.medicationQuery:
        return await _handleMedicationQuery(userId, message);

      case ChatIntent.general:
        return _handleGeneralQuery(message);
    }
  }

  /// Handle contact doctor request
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
        return 'I understand you need to contact a doctor. However, I couldn\'t find your profile. Please contact support.';
      }

      final patientData = patientDoc.data()!;
      final assignedDoctorId = patientData['assignedDoctorId'] as String?;

      if (assignedDoctorId == null) {
        return '🚨 I understand you\'re not feeling well and need medical attention.\n\n'
            'Unfortunately, you don\'t have an assigned doctor yet. Please:\n'
            '1. Visit the clinic in person for immediate care\n'
            '2. Call emergency services if it\'s urgent\n'
            '3. Contact clinic support to get assigned a doctor';
      }

      // Get doctor info
      final doctorDoc = await _firestore
          .collection('doctors')
          .doc(assignedDoctorId)
          .get();

      if (!doctorDoc.exists) {
        return 'I understand you need to contact a doctor, but there was an error retrieving your doctor\'s information. Please contact clinic support.';
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
          .collection('notifications')
          .add({
        'userId': assignedDoctorId,
        'title': '🚨 Urgent: Patient Needs Attention',
        'message': '${patientData['name']} is not feeling well: "$message"',
        'type': 'urgent_patient',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'metadata': {
          'patientId': userId,
          'patientName': patientData['name'],
        },
      });

      return '🚨 **Urgent Message Sent to Dr. $doctorName**\n\n'
          'I\'ve immediately notified Dr. $doctorName about your condition. '
          'They should respond shortly.\n\n'
          '**In the meantime:**\n'
          '• If this is a medical emergency, call emergency services immediately\n'
          '• Continue taking your prescribed medications as scheduled\n'
          '• Rest and stay hydrated\n'
          '• Monitor your symptoms\n\n'
          'Dr. $doctorName will contact you as soon as possible. '
          'If you don\'t hear back within 30 minutes and feel worse, '
          'please go to the nearest emergency room.';

    } catch (e) {
      debugPrint('Error handling contact doctor request: $e');
      return 'I understand you need to contact a doctor. There was a technical error. '
          'Please call the clinic directly or visit in person if urgent.';
    }
  }

  /// Handle appointment booking request
  String _handleAppointmentRequest() {
    return '📅 **Let me help you book an appointment!**\n\n'
        'Please tell me:\n'
        '1. Which doctor would you like to see? (or I can suggest based on your condition)\n'
        '2. What is the reason for your visit?\n'
        '3. When would you prefer? (date and time)\n\n'
        'Or simply tell me what\'s bothering you and I\'ll suggest the right specialist!';
  }

  /// Handle medication query
  Future<String> _handleMedicationQuery(String userId, String message) async {
    try {
      final medications = await _firestore
          .collection('patients')
          .doc(userId)
          .collection('medications')
          .get();

      if (medications.docs.isEmpty) {
        return '💊 You don\'t have any prescribed medications currently. '
            'If you think you need medication, please consult with your doctor.';
      }

      String response = '💊 **Your Current Medications:**\n\n';
      for (var doc in medications.docs) {
        final data = doc.data();
        final name = data['name'] ?? 'Unknown';
        final dosage = data['dosage'] ?? '';
        final times = (data['times'] as List<dynamic>?)?.join(', ') ?? '';

        response += '• **$name** $dosage\n';
        if (times.isNotEmpty) {
          response += '  Times: $times\n';
        }
        response += '\n';
      }

      response += '\n**Remember:**\n'
          '• Take medications at the scheduled times\n'
          '• Don\'t skip doses\n'
          '• If you have questions about side effects, contact your doctor\n\n'
          'If you need to contact your doctor, just let me know!';

      return response;
    } catch (e) {
      debugPrint('Error fetching medications: $e');
      return 'I had trouble fetching your medication information. Please try again.';
    }
  }

  /// Handle general query
  String _handleGeneralQuery(String message) {
    return 'I\'m here to help! I can assist you with:\n\n'
        '📅 **Booking appointments** - Just ask to book an appointment\n'
        '💊 **Medication info** - Ask about your medicines\n'
        '👨‍⚕️ **Contact your doctor** - Tell me if you\'re not feeling well\n'
        '🏥 **Health questions** - Ask me anything about your health\n\n'
        'What would you like to know?';
  }
}

enum ChatIntent {
  contactDoctor,
  bookAppointment,
  medicationQuery,
  general,
}