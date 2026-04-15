// routes/chatRoutes.js
// API routes for chat functionality

import express from 'express';
import { enhancedChatService } from '../services/enhancedChatService.js';

const router = express.Router();

/**
 * POST /api/chat
 * Main chat endpoint - handles both patient and doctor messages
 */
router.post('/chat', async (req, res) => {
  try {
    const { messages, userContext, role } = req.body;

    console.log('📨 Chat request received');
    console.log('   Role:', role);
    console.log('   Messages count:', messages?.length);

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

      console.log('👨‍⚕️ Processing doctor message...');
      response = await enhancedChatService.processDoctorMessage({
        message: messageText,
        doctorId,
        userContext,
        conversationHistory
      });

    } else {
      // Patient chat
      const userId = userContext?.userId || userContext?.patientId || 'unknown';

      console.log('🧑 Processing patient message...');
      response = await enhancedChatService.processPatientMessage({
        message: messageText,
        userId,
        conversationHistory
      });
    }

    console.log('✅ Chat processed successfully');
    // Return the response
    res.json(response);

  } catch (error) {
    console.error('❌ Chat API error:', error);

    res.status(500).json({
      message: "I'm having trouble connecting right now. Please try again.",
      error: process.env.NODE_ENV === 'development' ? error.message : undefined,
      actions: [],
      risk: 'low'
    });
  }
});

/**
 * POST /api/chat/bill
 * Chat about a specific bill analysis
 */
router.post('/chat/bill', async (req, res) => {
  try {
    const { question, billAnalysis } = req.body;

    console.log('💰 Bill chat request received');
    console.log('   Question:', question);
    console.log('   Bill total:', billAnalysis?.totalAmount);

    if (!question || !billAnalysis) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'Question and billAnalysis are required'
      });
    }

    // Import Gemini SDK
    const { GoogleGenerativeAI } = await import('@google/generative-ai');
    const { config } = await import('../config/config.js');

    const genAI = new GoogleGenerativeAI(config.gemini.apiKey);
    const model = genAI.getGenerativeModel({
      model: config.gemini.model,
      generationConfig: {
        temperature: 0.4, // Lower temperature for more factual responses
        maxOutputTokens: 1024,
      }
    });

    // Build comprehensive bill context
    const itemsList = billAnalysis.items?.map(item =>
      `- ${item.name || 'Unknown item'} (Qty: ${item.quantity || 1}) = RM ${item.price || 0} (Total: RM ${item.total_price || item.price || 0})`
    ).join('\n') || 'No items found';

    const flagsList = billAnalysis.flags?.map(flag =>
      `⚠️ ${flag.title || 'Issue'}: ${flag.description || ''} (Potential savings: RM ${flag.potential_savings || 0})`
    ).join('\n') || 'No issues detected';

    const billPrompt = `You are a helpful medical bill advisor for CareLoop. Answer the patient's question about their medical bill clearly and specifically.

BILL DETAILS:
📋 Pharmacy: ${billAnalysis.pharmacyName || 'Not specified'}
📅 Date: ${billAnalysis.billDate || 'Not specified'}
💰 Subtotal: RM ${billAnalysis.subtotal || 0}
💵 Tax: RM ${billAnalysis.tax || 0}
💳 Total Amount: RM ${billAnalysis.totalAmount || 0}

ITEMS ON BILL:
${itemsList}

ISSUES DETECTED:
${flagsList}

SUMMARY: ${billAnalysis.summary || 'No summary available'}

PATIENT'S QUESTION: "${question}"

INSTRUCTIONS:
1. Answer the patient's SPECIFIC question directly with concrete numbers and details from the bill
2. If they ask "how to save", give SPECIFIC actionable advice based on the flags and items
3. If they ask "why is X high", explain the SPECIFIC reason using the bill data
4. Use simple, patient-friendly language - avoid jargon
5. Be helpful and practical - focus on what they can DO
6. Always reference specific items or charges from their bill
7. If asking about savings, mention the EXACT potential savings amount (RM ${billAnalysis.potentialTotalSavings || 0})

Examples of GOOD responses:
- "Looking at your bill, the equipment charges are RM 150 because you used specialized monitoring equipment during your visit. This is standard for procedures requiring continuous monitoring."
- "You can save approximately RM ${billAnalysis.potentialTotalSavings || 0} by: [specific suggestions from the flags]"
- "The high charge for [specific item] at RM [amount] appears to be [explain based on flags or context]"

Do NOT give generic responses like "I can't provide financial advice" or "contact billing department" UNLESS the question truly cannot be answered from the bill data.

Answer naturally and conversationally - NO JSON, just plain text response.`;

    const result = await model.generateContent([{ text: billPrompt }]);
    const responseText = result.response.text();

    console.log('✅ Bill chat response generated');

    res.json({
      message: responseText,
      success: true
    });

  } catch (error) {
    console.error('❌ Bill chat error:', error);

    res.status(500).json({
      message: "I'm having trouble analyzing your bill right now. Please try again in a moment.",
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
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

    console.log('🔍 Bill analysis request received');
    console.log('   User ID:', userId);
    console.log('   Image size:', imageBase64 ? `${imageBase64.length} chars` : 'none');

    // Validate request
    if (!imageBase64) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'imageBase64 is required'
      });
    }

    // Import Gemini SDK
    const { GoogleGenerativeAI } = await import('@google/generative-ai');
    const { config } = await import('../config/config.js');

    const genAI = new GoogleGenerativeAI(config.gemini.apiKey);
    const model = genAI.getGenerativeModel({
      model: config.gemini.model,
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 4096,
      }
    });

    console.log('🤖 Calling Gemini Vision API for extraction...');

    // Step 1: Extract bill data
    const extractPrompt = `Extract structured data from this medical/pharmacy bill.

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

    const extractResult = await model.generateContent([
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: imageBase64
        }
      },
      { text: extractPrompt }
    ]);

    const extractedText = extractResult.response.text();
    console.log('✅ Extraction complete');

    const extractedData = parseGeminiJSON(extractedText);

    if (!extractedData.items || extractedData.items.length === 0) {
      return res.status(400).json({
        error: 'No bill items detected',
        message: 'Could not extract any items from the bill image. Please ensure the image is clear.'
      });
    }

    console.log(`   Found ${extractedData.items.length} items`);
    console.log('🤖 Calling Gemini for analysis...');

    // Step 2: Analyze the data
    const analyzePrompt = `Analyze this extracted medical bill data for patient-friendly insights.

Bill Data:
${JSON.stringify(extractedData)}

Return ONLY valid JSON:

{
  "items": [
    {
      "name": "string",
      "category": "Medicine|Consultation|Test|Other",
      "description": "Max 10 words patient-friendly description",
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
  "potential_total_savings": 0
}

Rules:
- Keep text concise and patient-friendly
- Return items in EXACT SAME ORDER as input
- Do not omit any items`;

    const analyzeResult = await model.generateContent([{ text: analyzePrompt }]);
    const analyzedText = analyzeResult.response.text();
    console.log('✅ Analysis complete');

    const analyzedData = parseGeminiJSON(analyzedText);

    // Step 3: Merge data
    const mergedItems = extractedData.items.map((extractedItem, index) => {
      const analyzedItem = analyzedData.items?.[index] || {};
      return {
        ...extractedItem,
        ...analyzedItem
      };
    });

    const finalData = {
      success: true,
      pharmacy_name: extractedData.pharmacy_name,
      bill_date: extractedData.bill_date,
      items: mergedItems,
      flags: analyzedData.flags || [],
      subtotal: extractedData.subtotal,
      tax: extractedData.tax,
      total_amount: extractedData.total_amount,
      summary: analyzedData.summary || 'Bill analyzed successfully.',
      suggestions: analyzedData.suggestions || [],
      potential_total_savings: analyzedData.potential_total_savings || 0
    };

    console.log('✅ Bill analysis complete');
    res.json(finalData);

  } catch (error) {
    console.error('❌ Bill analysis error:', error);

    res.status(500).json({
      error: 'Analysis failed',
      message: error.message || 'Failed to analyze bill. Please try again.',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

/**
 * POST /api/chat/image
 * Chat with image — used for bill/prescription scanning from the chat screen
 */
router.post('/chat/image', async (req, res) => {
  try {
    const { message, imageBase64, role, userId } = req.body;

    if (!imageBase64) {
      return res.status(400).json({
        error: 'Invalid request',
        message: 'imageBase64 is required'
      });
    }

    console.log('📸 Image chat request received');
    console.log('   User ID:', userId);
    console.log('   Image size:', `${imageBase64.length} chars`);

    // Import Gemini SDK
    const { GoogleGenerativeAI } = await import('@google/generative-ai');
    const { config } = await import('../config/config.js');

    const genAI = new GoogleGenerativeAI(config.gemini.apiKey);
    const model = genAI.getGenerativeModel({
      model: config.gemini.model,
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 2048,
      }
    });

    const prompt = `${message || 'Please analyse this medical document, bill, or prescription.'}

You are CareLoop AI analysing a medical document image for a patient.

If this is a BILL or RECEIPT:
- List all medications/services and their prices
- Flag anything that looks overpriced or unusual
- Give a friendly plain-language summary
- Suggest if they should ask their doctor or pharmacist anything

If this is a PRESCRIPTION:
- List the medications prescribed
- Explain what each one is typically used for (in simple terms)
- Note the dosage and frequency
- Remind them to take as prescribed

If this is a LAB REPORT:
- Explain the key results in simple patient-friendly language
- Note anything outside normal range
- Suggest discussing results with their doctor

Respond ONLY with valid JSON:
{
  "message": "Your friendly analysis here",
  "actions": [],
  "risk": "low",
  "appointment_intent": false,
  "check_medications": false,
  "feel_unwell": false,
  "unwell_symptoms": []
}`;

    const result = await model.generateContent([
      {
        inlineData: {
          mimeType: 'image/jpeg',
          data: imageBase64
        }
      },
      { text: prompt }
    ]);

    const responseText = result.response.text();
    console.log('✅ Gemini Vision analysis complete');

    // Parse the JSON response
    let parsed;
    try {
      let cleaned = responseText.trim()
        .replace(/```json\s*/g, '')
        .replace(/```\s*/g, '')
        .trim();
      const startIdx = cleaned.indexOf('{');
      const endIdx = cleaned.lastIndexOf('}');
      if (startIdx !== -1 && endIdx !== -1) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }
      parsed = JSON.parse(cleaned);
    } catch (_) {
      // Wrap plain text response
      parsed = {
        message: responseText.replace(/```json|```/g, '').trim(),
        actions: [],
        risk: 'low',
        appointment_intent: false,
        check_medications: false,
        feel_unwell: false,
        unwell_symptoms: []
      };
    }

    res.json(parsed);

  } catch (error) {
    console.error('Image chat error:', error);
    res.status(500).json({
      message: "I had trouble reading that image. Please make sure it's a clear photo and try again.",
      error: process.env.NODE_ENV === 'development' ? error.message : undefined,
      actions: [],
      risk: 'low'
    });
  }
});

/**
 * GET /api/health
 * Health check endpoint for Cloud Run
 */
router.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'CareLoop Agentic Backend'
  });
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

router.post('/send-notification', async (req, res) => {
  const { userId, title, message, type, metadata } = req.body;

  // Create notification in Firestore
  await db.collection('notifications').add({
    userId,
    title,
    message,
    type: type || 'general',
    isRead: false,
    timestamp: FieldValue.serverTimestamp(),
    metadata: metadata || {}
  });

  res.json({ success: true });
});

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
    console.error('Response was:', text.substring(0, 500));
    throw new Error('Failed to parse Gemini response as JSON');
  }
}

export default router;