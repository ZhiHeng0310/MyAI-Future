// routes/chatRoutes.js
// API routes for chat functionality

import express from 'express';
import { enhancedChatService } from '../services/enhancedChatService.js';
import { getFirestore } from '../config/firebase.js';

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

  } } catch (error) {
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