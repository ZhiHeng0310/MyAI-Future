// services/aiService.js
// AI Service for Report Generation and Summarization with Risk Detection

import { GoogleGenerativeAI } from '@google/generative-ai';
import { config } from '../config/config.js';

class AIService {
  constructor() {
    this.initialized = false;
    this.genAI = null;
    this.model = null;
  }

  /**
   * Initialize Gemini AI
   */
  async initialize() {
    if (this.initialized) return;

    try {
      if (!config.gemini.apiKey) {
        throw new Error('GEMINI_API_KEY not configured');
      }

      this.genAI = new GoogleGenerativeAI(config.gemini.apiKey);
      this.model = this.genAI.getGenerativeModel({
        model: config.gemini.model,
        generationConfig: {
          temperature: 0.4, // Lower for more accurate medical reports
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 4096,
        },
      });

      this.initialized = true;
      console.log('✅ AI Service initialized successfully');
    } catch (error) {
      console.error('❌ Error initializing AI Service:', error);
      throw error;
    }
  }

  /**
   * Generate Body Check Report with Risk Detection
   * @param {Object} vitalData - Patient vital signs data
   * @param {Object} patientInfo - Patient information
   * @returns {Promise<Object>} - Generated report with risk assessment
   */
  async generateBodyCheckReport(vitalData, patientInfo) {
    if (!this.initialized) {
      await this.initialize();
    }

    try {
      const prompt = `You are an AI medical assistant generating a comprehensive body check report.

PATIENT INFORMATION:
- Name: ${patientInfo.name || 'Unknown'}
- Age: ${patientInfo.age || 'Unknown'}
- Gender: ${patientInfo.gender || 'Unknown'}
- Patient ID: ${patientInfo.patientId || 'Unknown'}

VITAL SIGNS DATA:
- Blood Pressure: ${vitalData.bloodPressure?.systolic || 'N/A'}/${vitalData.bloodPressure?.diastolic || 'N/A'} mmHg
- Heart Rate: ${vitalData.heartRate || 'N/A'} bpm
- Temperature: ${vitalData.temperature || 'N/A'} °C
- Oxygen Saturation (SpO2): ${vitalData.oxygenSaturation || 'N/A'} %
- Respiratory Rate: ${vitalData.respiratoryRate || 'N/A'} breaths/min
- Blood Sugar: ${vitalData.bloodSugar || 'N/A'} mg/dL
- Weight: ${vitalData.weight || 'N/A'} kg
- Height: ${vitalData.height || 'N/A'} cm
- BMI: ${vitalData.bmi || 'N/A'}

MEDICAL HISTORY (if available):
${vitalData.medicalHistory || 'No medical history provided'}

SYMPTOMS (if any):
${vitalData.symptoms || 'No symptoms reported'}

INSTRUCTIONS:
Generate a comprehensive medical body check report in JSON format with the following structure:

{
  "report_id": "unique_id",
  "patient_name": "patient name",
  "patient_id": "patient id",
  "date": "ISO date string",
  "overall_risk_level": "low|medium|high|critical",
  "summary": "Brief overall health summary (2-3 sentences)",
  "vital_signs_analysis": {
    "blood_pressure": {
      "value": "systolic/diastolic mmHg",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "heart_rate": {
      "value": "bpm",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "temperature": {
      "value": "°C",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "oxygen_saturation": {
      "value": "%",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "respiratory_rate": {
      "value": "breaths/min",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "blood_sugar": {
      "value": "mg/dL",
      "status": "normal|borderline|abnormal",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    },
    "bmi": {
      "value": "BMI value",
      "status": "underweight|normal|overweight|obese",
      "risk_level": "low|medium|high",
      "interpretation": "Clinical interpretation",
      "recommendation": "Action to take"
    }
  },
  "risk_alerts": [
    {
      "title": "Alert title",
      "severity": "low|medium|high|critical",
      "description": "Detailed description of the risk",
      "affected_vitals": ["vital sign names"],
      "recommended_action": "What should be done"
    }
  ],
  "recommendations": [
    "Specific recommendation 1",
    "Specific recommendation 2"
  ],
  "follow_up_required": true/false,
  "follow_up_urgency": "immediate|urgent|routine|none",
  "follow_up_reason": "Why follow-up is needed"
}

RISK ASSESSMENT GUIDELINES:
- Blood Pressure: Normal (90-120/60-80), Borderline (120-139/80-89), High (≥140/90)
- Heart Rate: Normal (60-100 bpm), Borderline (<60 or >100), Abnormal (<50 or >120)
- Temperature: Normal (36.1-37.2°C), Fever (>37.5°C), Hypothermia (<35°C)
- SpO2: Normal (95-100%), Low (90-94%), Critical (<90%)
- Blood Sugar: Normal (70-100 fasting), Prediabetic (100-125), Diabetic (>125)

Set overall_risk_level to:
- "low" if all vitals are normal
- "medium" if 1-2 vitals are borderline
- "high" if any vital is abnormal or 3+ are borderline
- "critical" if any vital indicates immediate danger

Return ONLY valid JSON, no markdown, no explanations.`;

      const result = await this.model.generateContent(prompt);
      const responseText = result.response.text();

      console.log('✅ Body check report generated');

      // Parse JSON response
      const reportData = this.parseGeminiJSON(responseText);

      // Add metadata
      reportData.generated_at = new Date().toISOString();
      reportData.generated_by = 'AI Assistant';

      return {
        success: true,
        report: reportData
      };

    } catch (error) {
      console.error('❌ Error generating body check report:', error);
      throw error;
    }
  }

  /**
   * Summarize Medical Report for Patient with Risk Detection
   * @param {Object} reportData - Full medical report data
   * @param {Object} patientInfo - Patient information
   * @returns {Promise<Object>} - Patient-friendly summary with risk explanation
   */
  async summarizeReportForPatient(reportData, patientInfo) {
    if (!this.initialized) {
      await this.initialize();
    }

    try {
      const prompt = `You are an AI medical assistant creating a patient-friendly summary of a medical report.

PATIENT INFORMATION:
- Name: ${patientInfo.name || 'Unknown'}
- Patient ID: ${patientInfo.patientId || 'Unknown'}

FULL MEDICAL REPORT:
${JSON.stringify(reportData, null, 2)}

INSTRUCTIONS:
Create a patient-friendly summary that:
1. Uses simple, non-medical language
2. Explains what the numbers mean in everyday terms
3. Highlights any concerns or risks clearly
4. Provides actionable next steps
5. Is encouraging and supportive in tone

Generate the summary in JSON format:

{
  "summary_id": "unique_id",
  "patient_name": "patient name",
  "patient_id": "patient id",
  "date": "ISO date string",
  "overall_status": "Your health is...",
  "risk_level": "low|medium|high|critical",
  "risk_explanation": "Patient-friendly explanation of any risks",
  "key_findings": [
    {
      "title": "Finding title (e.g., 'Your Blood Pressure')",
      "status": "good|needs attention|concerning",
      "explanation": "What this means in simple terms",
      "icon": "✓|⚠️|❌"
    }
  ],
  "what_this_means": "Overall health explanation in 2-3 simple sentences",
  "things_to_watch": [
    "Simple health tip 1",
    "Simple health tip 2"
  ],
  "next_steps": [
    {
      "action": "What to do",
      "urgency": "immediate|soon|routine",
      "reason": "Why it's important"
    }
  ],
  "questions_to_ask_doctor": [
    "Suggested question 1",
    "Suggested question 2"
  ],
  "positive_notes": [
    "Encouraging observation 1",
    "Encouraging observation 2"
  ]
}

TONE GUIDELINES:
- Use "you" and "your" (e.g., "Your blood pressure is...")
- Avoid medical jargon
- Be honest but encouraging
- Focus on what the patient CAN do
- Use analogies when helpful (e.g., "Your heart rate is like a car engine running smoothly")

Return ONLY valid JSON, no markdown, no explanations.`;

      const result = await this.model.generateContent(prompt);
      const responseText = result.response.text();

      console.log('✅ Patient summary generated');

      // Parse JSON response
      const summaryData = this.parseGeminiJSON(responseText);

      // Add metadata
      summaryData.generated_at = new Date().toISOString();
      summaryData.original_report_id = reportData.report_id;

      return {
        success: true,
        summary: summaryData
      };

    } catch (error) {
      console.error('❌ Error generating patient summary:', error);
      throw error;
    }
  }

  /**
   * Parse Gemini JSON response (handles markdown code blocks)
   */
  parseGeminiJSON(text) {
    try {
      let cleaned = text.trim();

      // Remove markdown code blocks
      cleaned = cleaned.replace(/```json\s*/g, '');
      cleaned = cleaned.replace(/```\s*/g, '');
      cleaned = cleaned.trim();

      // Find JSON object
      const startIdx = cleaned.indexOf('{');
      const endIdx = cleaned.lastIndexOf('}');

      if (startIdx === -1 || endIdx === -1) {
        throw new Error('No valid JSON found in response');
      }

      const jsonStr = cleaned.substring(startIdx, endIdx + 1);
      return JSON.parse(jsonStr);
    } catch (error) {
      console.error('❌ JSON parse error:', error);
      console.error('Response was:', text.substring(0, 500));
      throw new Error('Failed to parse Gemini response as JSON');
    }
  }
}

// Export singleton instance
export const aiService = new AIService();
export default aiService;