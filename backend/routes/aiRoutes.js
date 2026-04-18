// routes/aiRoutes.js
// API routes for AI-powered features
// routes/aiRoutes.js
// API routes for AI-powered features

import express from 'express';
import admin from 'firebase-admin';
import { aiService } from '../services/aiService.js';
import { getFirestore } from '../config/firebase.js';

const db = getFirestore();

const router = express.Router();

/**
 * POST /api/ai/generate-report
 * Generate AI body check report with risk detection
 */
router.post('/generate-report', async (req, res) => {
  try {
    const { vitalData, patientInfo } = req.body;

    console.log('📊 AI Report Generation Request');
    console.log('   Patient:', patientInfo?.name);
    console.log('   Patient ID:', patientInfo?.patientId);

    // Validate request
    if (!vitalData) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request',
        message: 'vitalData is required'
      });
    }

    if (!patientInfo || !patientInfo.patientId) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request',
        message: 'patientInfo with patientId is required'
      });
    }

    // Generate report using AI service
    const result = await aiService.generateBodyCheckReport(vitalData, patientInfo);

    // Store report in Firestore
    const reportRef = db.collection('medical_reports').doc();
    const reportId = reportRef.id;

    const reportDocument = {
      reportId: reportId,
      patientId: patientInfo.patientId,
      patientName: patientInfo.name,
      doctorId: patientInfo.doctorId || null,
      reportType: 'body_check',
      reportData: result.report,
      vitalData: vitalData,
      createdAt: new Date().toISOString(),
      createdBy: 'AI_SYSTEM',
      status: 'generated'
    };

    await reportRef.set(reportDocument);

    console.log('✅ Report generated and stored:', reportId);

    res.json({
      success: true,
      reportId: reportId,
      report: result.report,
      message: 'Body check report generated successfully'
    });

  } catch (error) {
    console.error('❌ Generate report error:', error);

    res.status(500).json({
      success: false,
      error: 'Report generation failed',
      message: error.message || 'Failed to generate report. Please try again.',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

/**
 * POST /api/ai/summarize-report
 * Summarize medical report for patient with risk detection
 */
router.post('/summarize-report', async (req, res) => {
  try {
    const { reportId, reportData, patientInfo } = req.body;

    console.log('📝 AI Report Summarization Request');
    console.log('   Report ID:', reportId);
    console.log('   Patient:', patientInfo?.name);

    // Validate request
    if (!reportData) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request',
        message: 'reportData is required'
      });
    }

    if (!patientInfo || !patientInfo.patientId) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request',
        message: 'patientInfo with patientId is required'
      });
    }

    // Generate patient-friendly summary using AI service
    const result = await aiService.summarizeReportForPatient(reportData, patientInfo);

    // Store summary in Firestore
    const summaryRef = db.collection('report_summaries').doc();
    const summaryId = summaryRef.id;

    const summaryDocument = {
      summaryId: summaryId,
      reportId: reportId || null,
      patientId: patientInfo.patientId,
      patientName: patientInfo.name,
      summaryData: result.summary,
      createdAt: new Date().toISOString(),
      createdBy: 'AI_SYSTEM',
      sentToPatient: false
    };

    await summaryRef.set(summaryDocument);

    console.log('✅ Summary generated and stored:', summaryId);

    res.json({
      success: true,
      summaryId: summaryId,
      summary: result.summary,
      message: 'Report summary generated successfully'
    });

  } catch (error) {
    console.error('❌ Summarize report error:', error);

    res.status(500).json({
      success: false,
      error: 'Summarization failed',
      message: error.message || 'Failed to summarize report. Please try again.',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

/**
 * POST /api/ai/send-summary-to-patient
 * Send report summary to patient's inbox
 */
router.post('/send-summary-to-patient', async (req, res) => {
  try {
    const { summaryId, patientId, doctorId, summaryData } = req.body;

    console.log('📬 Send Summary to Patient Request');
    console.log('   Summary ID:', summaryId);
    console.log('   Patient ID:', patientId);

    // Validate request
    if (!summaryId || !patientId || !summaryData) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request',
        message: 'summaryId, patientId, and summaryData are required'
      });
    }

    // Create inbox message for patient
    const inboxRef = db.collection('inbox_messages').doc();

    const inboxMessage = {
      messageId: inboxRef.id,
      patientId: patientId,
      doctorId: doctorId || 'AI_SYSTEM',
      title: '📋 Your Body Check Report Summary',
      type: 'report_summary',
      content: summaryData,
      summaryId: summaryId,
      createdAt: new Date().toISOString(),
      isRead: false,
      priority: summaryData.risk_level === 'high' || summaryData.risk_level === 'critical' ? 'high' : 'normal'
    };

    await inboxRef.set(inboxMessage);

    // Update summary document to mark as sent
    await db.collection('report_summaries').doc(summaryId).update({
      sentToPatient: true,
      sentAt: new Date().toISOString(),
      inboxMessageId: inboxRef.id
    });

    // Create notification for patient
    const notificationRef = db.collection('notifications').doc();

    await notificationRef.set({
      userId: patientId,
      title: '📋 New Health Report',
      message: `Your body check report summary is ready. ${summaryData.risk_level === 'high' || summaryData.risk_level === 'critical' ? '⚠️ Please review it soon.' : 'Tap to view your report.'}`,
      type: 'general', // Use general type for custom notifications
      isRead: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        type: 'report_summary', // Custom type identifier
        summaryId: summaryId,
        inboxMessageId: inboxRef.id,
        riskLevel: summaryData.risk_level
      }
    });

    console.log('✅ Summary sent to patient inbox');

    res.json({
      success: true,
      inboxMessageId: inboxRef.id,
      message: 'Summary sent to patient successfully'
    });

  } catch (error) {
    console.error('❌ Send summary error:', error);

    res.status(500).json({
      success: false,
      error: 'Send failed',
      message: error.message || 'Failed to send summary to patient. Please try again.',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

/**
 * GET /api/ai/reports/:patientId
 * Get all reports for a patient
 */
router.get('/reports/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    console.log('📚 Fetch Reports Request');
    console.log('   Patient ID:', patientId);

    const reportsSnapshot = await db.collection('medical_reports')
      .where('patientId', '==', patientId)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const reports = [];
    reportsSnapshot.forEach(doc => {
      reports.push({
        id: doc.id,
        ...doc.data()
      });
    });

    console.log(`✅ Found ${reports.length} reports`);

    res.json({
      success: true,
      reports: reports,
      count: reports.length
    });

  } catch (error) {
    console.error('❌ Fetch reports error:', error);

    res.status(500).json({
      success: false,
      error: 'Fetch failed',
      message: error.message || 'Failed to fetch reports. Please try again.'
    });
  }
});

/**
 * GET /api/ai/summaries/:patientId
 * Get all summaries for a patient
 */
router.get('/summaries/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    console.log('📚 Fetch Summaries Request');
    console.log('   Patient ID:', patientId);

    const summariesSnapshot = await db.collection('report_summaries')
      .where('patientId', '==', patientId)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const summaries = [];
    summariesSnapshot.forEach(doc => {
      summaries.push({
        id: doc.id,
        ...doc.data()
      });
    });

    console.log(`✅ Found ${summaries.length} summaries`);

    res.json({
      success: true,
      summaries: summaries,
      count: summaries.length
    });

  } catch (error) {
    console.error('❌ Fetch summaries error:', error);

    res.status(500).json({
      success: false,
      error: 'Fetch failed',
      message: error.message || 'Failed to fetch summaries. Please try again.'
    });
  }
});

export default router;