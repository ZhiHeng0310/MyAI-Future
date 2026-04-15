// server.js
// Main server file for CareLoop Agentic Backend

import express from 'express';
import cors from 'cors';

console.log("Importing config...");
import { config } from './config/config.js';

console.log("Importing firebase...");
import { initializeFirebase } from './config/firebase.js';

console.log("Importing gemini...");
import { geminiService } from './services/geminiService.js';

console.log("Importing routes...");
import chatRoutes from './routes/chatRoutes.js';
import aiRoutes from './routes/aiRoutes.js';

console.log("Importing rate limit...");
import rateLimit from 'express-rate-limit';

console.log('🔥 VERSION WITH ANALYZE BILL ROUTE LOADED');

process.on('unhandledRejection', (err) => {
  console.error('UNHANDLED REJECTION:', err);
});

process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION:', err);
});

// Create Express app
const app = express();
app.set('trust proxy', 1);

const port = Number(process.env.PORT) || 8080;

// Middleware
app.use(cors({
  origin: "*",
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.options('*', cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api/', (req, res, next) => {
  if (req.method === 'OPTIONS') return next(); // 🔥 skip preflight
  return limiter(req, res, next);
});
// Mount API routes
app.use('/api', chatRoutes);
app.use('/api/ai', aiRoutes);

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
      test: '/api/test',
      ai_generate_report: '/api/ai/generate-report',
      ai_summarize_report: '/api/ai/summarize-report',
      ai_send_summary: '/api/ai/send-summary-to-patient'
    }
  });
});

// Mount API routes

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

  let server;

  try {
    // 1. START EXPRESS IMMEDIATELY (CRITICAL)
    server = app.listen(port, '0.0.0.0', () => {
      console.log(`✅ Server running on port ${port}`);
    });

    // 2. SAFE INIT WRAPPER (NO CRASH ALLOWED)
    (async () => {
      try {
        console.log('🔥 Initializing Firebase...');
        initializeFirebase();
        console.log('✅ Firebase ready');
      } catch (err) {
        console.error('⚠️ Firebase init failed:', err.message);
      }

      try {
        console.log('🤖 Initializing Gemini...');
        await geminiService.initialize();
        console.log('✅ Gemini ready');
      } catch (err) {
        console.error('⚠️ Gemini init failed:', err.message);
      }
    })();

  } catch (err) {
    console.error('💥 FATAL SERVER CRASH:', err);
    process.exit(1);
  }

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

// Start the server
startServer();

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

// Start the server
startServer();