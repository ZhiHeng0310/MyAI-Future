// screens/patient/patient_report_viewer_screen.dart
// Patient Report Viewer - View AI-generated health reports with PDF download

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/ai_summary_model.dart';
import '../../widgets/risk_badge.dart';

class PatientReportViewerScreen extends StatelessWidget {
  final AISummary summary;
  final String? reportId;

  const PatientReportViewerScreen({
    Key? key,
    required this.summary,
    this.reportId,
  }) : super(key: key);

  Future<void> _downloadPDF(BuildContext context) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final pdf = await _generatePDF();

      // Close loading
      if (context.mounted) Navigator.pop(context);

      // Show PDF preview with download/share options
      await Printing.layoutPdf(
        onLayout: (format) => pdf.save(),
        name: 'health_report_${summary.summaryId}.pdf',
      );
    } catch (e) {
      // Close loading if still open
      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<pw.Document> _generatePDF() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.teal, width: 2),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '📋 Your Health Report',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Patient-Friendly Summary',
                  style: const pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Patient Info
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  summary.patientName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Report Date: ${_formatDate(summary.date)}',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Risk Level
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _getRiskColorPDF(summary.riskLevel),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  '⚠️',
                  style: const pw.TextStyle(fontSize: 24),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Risk Level: ${summary.riskLevel.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      if (summary.riskExplanation.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text(
                          summary.riskExplanation,
                          style: const pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Overall Status
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.teal),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Overall Status',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  summary.overallStatus,
                  style: const pw.TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Key Findings
          pw.Text(
            'Key Findings',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal,
            ),
          ),
          pw.SizedBox(height: 12),

          ...summary.keyFindings.map((finding) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _getFindingColorPDF(finding.status)),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  finding.icon,
                  style: const pw.TextStyle(fontSize: 20),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        finding.title,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        finding.explanation,
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )),

          pw.SizedBox(height: 24),

          // What This Means
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'What This Means',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  summary.whatThisMeans,
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Next Steps
          if (summary.nextSteps.isNotEmpty) ...[
            pw.Text(
              'Next Steps',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
              ),
            ),
            pw.SizedBox(height: 12),

            ...summary.nextSteps.map((step) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: step.urgency == 'immediate' ? PdfColors.red50 : PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text(
                        step.action,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (step.urgency != 'routine') ...[
                        pw.SizedBox(width: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: step.urgency == 'immediate' ? PdfColors.red : PdfColors.orange,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            step.urgency.toUpperCase(),
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    step.reason,
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )),

            pw.SizedBox(height: 24),
          ],

          // Positive Notes
          if (summary.positiveNotes.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '✨ Positive Notes',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green900,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  ...summary.positiveNotes.map((note) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('✓ ', style: const pw.TextStyle(color: PdfColors.green)),
                        pw.Expanded(
                          child: pw.Text(note, style: const pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],

          // Footer
          pw.SizedBox(height: 32),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generated by CareLoop AI • ${_formatDate(summary.generatedAt)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center,
          ),
          pw.Text(
            'This report is for informational purposes. Consult your doctor for medical advice.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    return pdf;
  }

  PdfColor _getRiskColorPDF(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return PdfColors.green;
      case 'medium':
        return PdfColors.orange;
      case 'high':
        return PdfColors.red;
      case 'critical':
        return PdfColors.purple;
      default:
        return PdfColors.grey;
    }
  }

  PdfColor _getFindingColorPDF(String status) {
    switch (status.toLowerCase()) {
      case 'good':
        return PdfColors.green;
      case 'needs attention':
        return PdfColors.orange;
      case 'concerning':
        return PdfColors.red;
      default:
        return PdfColors.grey;
    }
  }

  Color _getRiskColorUI(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getFindingColorUI(String status) {
    switch (status.toLowerCase()) {
      case 'good':
        return Colors.green;
      case 'needs attention':
        return Colors.orange;
      case 'concerning':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Health Report'),
        backgroundColor: const Color(0xFF00C9B8),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download PDF',
            onPressed: () => _downloadPDF(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '📋 Your Health Report',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00C9B8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                summary.patientName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(summary.date),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        RiskBadge(risk: summary.riskLevel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Risk Explanation
            if (summary.riskExplanation.isNotEmpty) ...[
              Card(
                color: _getRiskColorUI(summary.riskLevel).withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: _getRiskColorUI(summary.riskLevel),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'About Your Health',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(summary.riskExplanation),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Overall Status
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      summary.overallStatus,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Key Findings
            const Text(
              'Key Findings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            ...summary.keyFindings.map((finding) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getFindingColorUI(finding.status),
                  child: Text(
                    finding.icon,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                title: Text(
                  finding.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(finding.explanation),
              ),
            )),
            const SizedBox(height: 16),

            // What This Means
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What This Means',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(summary.whatThisMeans),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Next Steps
            if (summary.nextSteps.isNotEmpty) ...[
              const Text(
                'Next Steps',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              ...summary.nextSteps.map((step) => Card(
                color: step.urgency == 'immediate' ? Colors.red.shade50 : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              step.action,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (step.urgency != 'routine')
                            Chip(
                              label: Text(step.urgency.toUpperCase()),
                              backgroundColor: step.urgency == 'immediate'
                                  ? Colors.red
                                  : Colors.orange,
                              labelStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(step.reason),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 16),
            ],

            // Positive Notes
            if (summary.positiveNotes.isNotEmpty) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✨ Positive Notes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...summary.positiveNotes.map((note) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(note)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Download Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _downloadPDF(context),
                icon: const Icon(Icons.download),
                label: const Text('Download PDF Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C9B8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer
            Center(
              child: Column(
                children: [
                  Text(
                    'Generated by CareLoop AI',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    _formatDate(summary.generatedAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}