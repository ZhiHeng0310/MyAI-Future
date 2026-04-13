// routes/chatRoutes.js
// API routes for chat functionality

import express from 'express';
import { enhancedChatService } from '../services/enhancedChatService.js';
import { getFirestore } from '../config/firebase.js';
import { geminiService } from '../services/geminiService.js';

const router = express.Router();

// Validation middleware
function validateChatRequest(req, res, next) {
  const { messages, role } = req.body;

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({
      error: 'Invalid request',
      message: 'Messages array is required and must not be empty'
    });
  }

  if (!role || !['patient', 'doctor'].includes(role)) {
    return res.status(400).json({
      error: 'Invalid request',
      message: 'Role must be either "patient" or "doctor"'
    });
  }

  next();
}

/**
 * POST /api/chat
 * Main chat endpoint - handles both patient and doctor messages
 */
router.post('/chat', validateChatRequest, async (req, res) => {
  try {
    const { messages, userContext, role } = req.body;

    // Validate request
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'Messages array is required and must not be empty'
      });
    }

    if (!role || !['patient', 'doctor'].includes(role)) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'Role must be either "patient" or "doctor"'
      });
    }

    // Extract the latest user message
    const latestMessage = messages[messages.length - 1];
    const messageText = latestMessage.content || latestMessage.text || latestMessage.message;

    if (!messageText) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'Message content is required'
      });
    }

    // Build conversation history (exclude the latest message)
    const conversationHistory = messages.slice(0, -1).map(msg => ({
      role: msg.role === 'user' ? 'user' : 'assistant',
      content: msg.content || msg.text || msg.message
    }));

    let response;

    // Process based on role
    if (role === 'doctor') {
      // Doctor chat
      const doctorId = userContext?.doctorId || userContext?.userId || 'unknown';

      response = await enhancedChatService.processDoctorMessage({
        message: messageText,
        doctorId,
        userContext,
        conversationHistory
      });

    } else {
      // Patient chat
      const userId = userContext?.userId || userContext?.patientId || 'unknown';

      response = await enhancedChatService.processPatientMessage({
        message: messageText,
        userId,
        conversationHistory
      });
    }

    // Return the response
    res.json(response);

  } catch (error) {
      console.error('Chat API error:', error);

      // Determine appropriate status code
      const statusCode = error.statusCode || 500;

      res.status(statusCode).json({
        message: "I'm having trouble connecting right now. Please try again.",
        error: process.env.NODE_ENV === 'development' ? error.message : undefined,
        actions: [],
        risk: 'low',
        timestamp: new Date().toISOString()
      });
    }
});

/**
 * POST /api/analyze-bill
 * Analyze medical bill image using Gemini Vision
 */
router.post('/analyze-bill', async (req, res) => {
  try {
    const { imageBase64, userId } = req.body;

    // Validate request
    if (!imageBase64) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'imageBase64 is required'
      });
    }

    console.log('🔍 Analyzing bill for user:', userId);

    // Step 1: Extract bill data using Gemini Vision
    const extractedData = await extractBillData(imageBase64);

    if (!extractedData.items || extractedData.items.length === 0) {
      return res.status(400).json({
        error: 'No bill items detected',
        message: 'Could not extract any items from the bill image'
      });
    }

    // Step 2: Analyze the extracted bill
    const analyzedData = await analyzeBillData(extractedData);

    // Step 3: Merge extraction + analysis
    const mergedData = mergeBillData(extractedData, analyzedData);

    // Step 4: Return complete analysis
    res.json({
      success: true,
      pharmacy_name: mergedData.pharmacy_name,
      bill_date: mergedData.bill_date,
      items: mergedData.items,
      flags: mergedData.flags,
      subtotal: mergedData.subtotal,
      tax: mergedData.tax,
      total_amount: mergedData.total_amount,
      summary: mergedData.summary,
      suggestions: mergedData.suggestions,
      potential_total_savings: mergedData.potential_total_savings
    });

  } catch (error) {
    console.error('❌ Bill analysis error:', error);

    res.status(500).json({
      error: 'Analysis failed',
      message: error.message || 'Failed to analyze bill',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

/**
 * Extract bill data from image using Gemini Vision
 */
async function extractBillData(imageBase64) {
  const { geminiService } = await import('../services/geminiService.js');

  if (!geminiService.initialized) {
    await geminiService.initialize();
  }

  // Import Google AI SDK
  const { GoogleGenerativeAI } = await import('@google/generative-ai');
  const { config } = await import('../config/config.js');

  const genAI = new GoogleGenerativeAI(config.gemini.apiKey);
  const model = genAI.getGenerativeModel({
    model: process.env.GEMINI_MODEL,
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 2048,
    }
  });

  const prompt = `Extract structured data from this medical/pharmacy bill.

Return ONLY valid JSON in this exact format:

{
  "pharmacy_name": "string",
  "bill_date": "string",
  "items": [
    {
      "name": "string",
      "quantity": number,
      "price": number,
      "total_price": number
    }
  ],
  "subtotal": number,
  "tax": number,
  "total_amount": number
}

Rules:
- Extract visible values only
- Do not guess missing values
- Return valid JSON only, no markdown, no explanations`;

  const result = await model.generateContent([
    {
      inlineData: {
        mimeType: "image/jpeg",
        data: imageBase64
      }
    },
    { text: prompt }
  ]);

  const responseText = result.response.text();
  return parseGeminiJSON(responseText);
}

/**
 * Analyze extracted bill data
 */
async function analyzeBillData(extractedBill) {
  const { geminiService } = await import('../services/geminiService.js');

  const prompt = `Analyze this extracted medical bill data for patient-friendly insights.

Bill Data:
${JSON.stringify(extractedBill)}

Return ONLY valid JSON:

{
  "items": [
    {
      "name": "string",
      "category": "Medicine|Consultation|Test|Other",
      "description": "Max 8 words patient-friendly description",
      "is_price_normal": true,
      "price_warning": "Short warning if abnormal",
      "alternative_suggestion": "Cheaper option if available"
    }
  ],
  "flags": [
    {
      "type": "duplicate|overpriced|calculation_error|missing_info",
      "severity": "low|medium|high",
      "title": "Short title",
      "description": "Patient-friendly explanation",
      "affected_items": ["Item Name"],
      "potential_savings": 0
    }
  ],
  "summary": "Overall bill assessment in 2 sentences max",
  "suggestions": [
    "Suggestion 1",
    "Suggestion 2"
  ],
  "potential_total_savings": number
}

Rules:
- Keep text concise and patient-friendly
- Return items in EXACT SAME ORDER as input
- Do not omit any items
- One analysis item per input item`;

  const response = await geminiService.generateResponse(
    prompt,
    'You are a medical bill analysis expert. Analyze bills accurately and provide helpful insights.',
    []
  );

  // If response is already an object, return it
  if (typeof response === 'object') {
    return response;
  }

  // Otherwise parse the text
  return parseGeminiJSON(response);
}

/**
 * Merge extracted and analyzed data
 */
function mergeBillData(extracted, analyzed) {
  const extractedItems = extracted.items || [];
  const analyzedItems = analyzed.items || [];

  const mergedItems = extractedItems.map((extractedItem, index) => {
    const analyzedItem = analyzedItems[index] || {};
    return {
      ...extractedItem,
      ...analyzedItem
    };
  });

  return {
    ...extracted,
    ...analyzed,
    items: mergedItems
  };
}

/**
 * Parse Gemini JSON response (handles markdown code blocks)
 */
function parseGeminiJSON(text) {
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
    console.error('Response was:', text);
    throw new Error('Failed to parse Gemini response as JSON');
  }
}

/**
 * POST /api/chat/image
 * Image chat endpoint - handles messages with images
 */
router.post('/chat/image', async (req, res) => {
  try {
    // You'll need to add multer middleware for file upload
    const message = req.body.message || '';
    const patientId = req.body.patientId;

    // For now, return a placeholder response
    // TODO: Implement Gemini Vision API integration
    res.json({
      message: "📸 I can see the image! Image analysis will be implemented soon.",
      actions: [],
      risk: 'low',
      documentAnalysis: {
        detected: false,
        type: null,
        extractedText: '',
        medications: []
      }
    });

  } catch (error) {
    console.error('Image chat error:', error);
    res.status(500).json({
      message: "Failed to process image.",
      error: error.message,
      actions: [],
      risk: 'low'
    });
  }
});

/**
 * GET /api/health
 * Health check endpoint for Cloud Run
 */
router.get('/health', async (req, res) => {
  try {
    // Check Gemini connection
    const geminiReady = geminiService.initialized;

    // Check Firebase connection
    let firestoreReady = false;
    try {
      const db = getFirestore();
      await db.collection('health_check').limit(1).get();
      firestoreReady = true;
    } catch (e) {
      console.error('Firestore health check failed:', e);
    }

    const isHealthy = geminiReady && firestoreReady;

    res.status(isHealthy ? 200 : 503).json({
      status: isHealthy ? 'healthy' : 'degraded',
      timestamp: new Date().toISOString(),
      service: 'CareLoop Agentic Backend',
      checks: {
        gemini: geminiReady ? 'ok' : 'failed',
        firestore: firestoreReady ? 'ok' : 'failed'
      }
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/test
 * Test endpoint for debugging
 */
router.post('/test', async (req, res) => {
  try {
    const { message } = req.body;

    res.json({
      received: message,
      timestamp: new Date().toISOString(),
      status: 'success'
    });
  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

export default router;