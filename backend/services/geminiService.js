// services/geminiService.js
// Gemini AI service for generating AI responses

import { GoogleGenerativeAI } from '@google/generative-ai';
import { config } from '../config/config.js';

class GeminiService {
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

      // Initialize model with configuration
      this.model = this.genAI.getGenerativeModel({
        model: config.gemini.model,
        generationConfig: {
          temperature: config.gemini.temperature,
          topK: config.gemini.topK,
          topP: config.gemini.topP,
          maxOutputTokens: config.gemini.maxTokens,
        },
        safetySettings: [
          {
            category: 'HARM_CATEGORY_HARASSMENT',
            threshold: 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            category: 'HARM_CATEGORY_HATE_SPEECH',
            threshold: 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            threshold: 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            category: 'HARM_CATEGORY_DANGEROUS_CONTENT',
            threshold: 'BLOCK_MEDIUM_AND_ABOVE',
          },
        ],
      });

      this.initialized = true;
      console.log('✅ Gemini AI initialized successfully');
    } catch (error) {
      console.error('❌ Error initializing Gemini AI:', error);
      throw error;
    }
  }

  /**
   * Generate response from Gemini with system instruction
   * @param {string} userMessage - User's message
   * @param {string} systemPrompt - System instruction
   * @param {Array} conversationHistory - Optional conversation history
   * @returns {Promise<Object>} - Parsed JSON response
   */
  async generateResponse(userMessage, systemPrompt, conversationHistory = []) {
    if (!this.initialized) {
      await this.initialize();
    }

    try {
      // Build the prompt with system instruction
      let fullPrompt = `${systemPrompt}\n\nUser message: "${userMessage}"`;

      // Add conversation history if provided
      if (conversationHistory && conversationHistory.length > 0) {
        const historyText = conversationHistory
          .map(msg => `${msg.role}: ${msg.content}`)
          .join('\n');
        fullPrompt = `${systemPrompt}\n\nConversation History:\n${historyText}\n\nUser message: "${userMessage}"`;
      }

      // Generate content
      const result = await this.model.generateContent(fullPrompt);
      const response = await result.response;
      const text = response.text();

      if (!text) {
        throw new Error('Empty response from Gemini');
      }

      // Parse JSON response
      try {
        // Clean the response (remove markdown code blocks if present)
        let cleanedText = text.trim();
        if (cleanedText.startsWith('```json')) {
          cleanedText = cleanedText.replace(/```json\n?/g, '').replace(/```\n?$/g, '');
        } else if (cleanedText.startsWith('```')) {
          cleanedText = cleanedText.replace(/```\n?/g, '').replace(/```\n?$/g, '');
        }

        const jsonResponse = JSON.parse(cleanedText);
        return jsonResponse;
      } catch (parseError) {
        console.error('JSON parse error:', parseError);
        console.error('Raw response:', text);

        // Return a safe fallback response
        return {
          message: text,
          actions: [],
          risk: 'low'
        };
      }

    } catch (error) {
      console.error('❌ Gemini API error:', error);
      throw error;
    }
  }

  /**
   * Generate response with streaming (for future use)
   * @param {string} prompt - The prompt
   * @returns {AsyncGenerator<string>} - Stream of text chunks
   */
  async *generateStreamResponse(prompt) {
    if (!this.initialized) {
      await this.initialize();
    }

    try {
      const result = await this.model.generateContentStream(prompt);

      for await (const chunk of result.stream) {
        const chunkText = chunk.text();
        if (chunkText) {
          yield chunkText;
        }
      }
    } catch (error) {
      console.error('❌ Gemini stream error:', error);
      yield 'I\'m having trouble connecting right now. Please try again.';
    }
  }
}

// Export singleton instance
export const geminiService = new GeminiService();
export default geminiService;