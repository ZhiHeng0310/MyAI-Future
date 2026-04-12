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

    res.status(500).json({
      message: "Brain fog! Try again.",
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

export default router;