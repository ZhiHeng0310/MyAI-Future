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
app.set('trust proxy', 1);

const port = process.env.PORT || config.port;

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
  console.log('🚀 Starting CareLoop Backend...');
  console.log(`📍 Port: ${port}`);

  // 1. START SERVER FIRST (CRITICAL)
  const server = app.listen(port, '0.0.0.0', () => {
    console.log(`✅ Server running on port ${port}`);
  });

  // 2. THEN INIT SERVICES (NON-BLOCKING SAFE)
  setTimeout(async () => {
    try {
      console.log('🔥 Initializing Firebase...');
      initializeFirebase();

      console.log('🤖 Initializing Gemini...');
      await geminiService.initialize();

      console.log('✅ All services ready');
    } catch (err) {
      console.error('⚠️ Service init failed (non-fatal):', err);
    }
  }, 1000);

  return server;
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

process.on('unhandledRejection', (err) => {
  console.error('UNHANDLED REJECTION:', err);
});

process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION:', err);
});

// Start the server
startServer();