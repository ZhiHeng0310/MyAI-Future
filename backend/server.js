// server.js
// Main server file for CareLoop Agentic Backend

import express from 'express';
import cors from 'cors';
import { config } from './config/config.js';
import { initializeFirebase } from './config/firebase.js';
import { geminiService } from './services/geminiService.js';
import chatRoutes from './routes/chatRoutes.js';
import rateLimit from 'express-rate-limit';

// Create Express app
const app = express();
const port = config.port;

// Middleware
app.use(cors({
  origin: "*",
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api/', limiter);
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Enhanced request logging
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  const ip = req.ip || req.connection.remoteAddress;
  console.log(`[${timestamp}] ${req.method} ${req.path} - IP: ${ip}`);

  // Log request body for debugging (remove in production)
  if (process.env.NODE_ENV !== 'production' && req.body) {
    console.log('Request body:', JSON.stringify(req.body, null, 2));
  }

  next();
});

// Request logging middleware
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.path}`);
  next();
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'CareLoop Agentic Backend',
    status: 'active',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    endpoints: {
      chat: '/api/chat',
      health: '/api/health',
      test: '/api/test'
    }
  });
});

// Mount API routes
app.use('/api', chatRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.method} ${req.path} not found`,
    availableEndpoints: {
      chat: 'POST /api/chat',
      health: 'GET /api/health',
      test: 'POST /api/test'
    }
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);

  res.status(err.status || 500).json({
    error: 'Internal Server Error',
    message: config.nodeEnv === 'production'
      ? 'An error occurred processing your request'
      : err.message,
    timestamp: new Date().toISOString()
  });
});

/**
 * Initialize services and start server
 */
async function startServer() {
  try {
    console.log('🚀 Starting CareLoop Backend...');
    console.log(`📍 Environment: ${config.nodeEnv}`);
    console.log(`📍 Port: ${port}`);

    // Initialize Firebase
    console.log('🔥 Initializing Firebase...');
    initializeFirebase();

    // Initialize Gemini AI
    console.log('🤖 Initializing Gemini AI...');
    await geminiService.initialize();
    console.log('✅ Gemini initialized');

    // Start listening
    app.listen(port, '0.0.0.0', () => {
      console.log('✅ CareLoop Backend is live!');
      console.log(`📡 Server running on http://0.0.0.0:${port}`);
      console.log(`🌐 Ready to receive requests`);
      console.log('\n📋 Available endpoints:');
      console.log(`   GET  /              - Service info`);
      console.log(`   POST /api/chat      - AI chat endpoint`);
      console.log(`   GET  /api/health    - Health check`);
      console.log(`   POST /api/test      - Test endpoint`);
      console.log('\n✨ Backend is ready for Cloud Run deployment!\n');
    });

  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 SIGTERM received, shutting down gracefully...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('🛑 SIGINT received, shutting down gracefully...');
  process.exit(0);
});

// Start the server
startServer();