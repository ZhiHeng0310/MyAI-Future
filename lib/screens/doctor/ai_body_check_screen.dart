// screens/doctor/ai_body_check_screen.dart
// AI Body Check Report Generator with Risk Detection

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/ai_service.dart';
import '../../models/ai_report_model.dart';
import '../../widgets/risk_badge.dart';

class AIBodyCheckScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? doctorId;

  const AIBodyCheckScreen({
    Key? key,
    required this.patientId,
    required this.patientName,
    this.doctorId,
  }) : super(key: key);

  @override
  State<AIBodyCheckScreen> createState() => _AIBodyCheckScreenState();
}

class _AIBodyCheckScreenState extends State<AIBodyCheckScreen> {
  final _formKey = GlobalKey<FormState>();

  // Vital signs controllers
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heartRateController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _respiratoryRateController = TextEditingController();
  final _bloodSugarController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _historyController = TextEditingController();

  bool _isGenerating = false;
  AIReport? _generatedReport;
  String? _reportId;

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _heartRateController.dispose();
    _temperatureController.dispose();
    _spo2Controller.dispose();
    _respiratoryRateController.dispose();
    _bloodSugarController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _symptomsController.dispose();
    _historyController.dispose();
    super.dispose();
  }

  Future<void> _generateReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Calculate BMI if height and weight provided
      double? bmi;
      if (_heightController.text.isNotEmpty && _weightController.text.isNotEmpty) {
        final heightM = double.parse(_heightController.text) / 100;
        final weight = double.parse(_weightController.text);
        bmi = weight / (heightM * heightM);
      }

      final vitalData = {
        'bloodPressure': {
          'systolic': _systolicController.text.isNotEmpty ? int.parse(_systolicController.text) : null,
          'diastolic': _diastolicController.text.isNotEmpty ? int.parse(_diastolicController.text) : null,
        },
        'heartRate': _heartRateController.text.isNotEmpty ? int.parse(_heartRateController.text) : null,
        'temperature': _temperatureController.text.isNotEmpty ? double.parse(_temperatureController.text) : null,
        'oxygenSaturation': _spo2Controller.text.isNotEmpty ? int.parse(_spo2Controller.text) : null,
        'respiratoryRate': _respiratoryRateController.text.isNotEmpty ? int.parse(_respiratoryRateController.text) : null,
        'bloodSugar': _bloodSugarController.text.isNotEmpty ? int.parse(_bloodSugarController.text) : null,
        'weight': _weightController.text.isNotEmpty ? double.parse(_weightController.text) : null,
        'height': _heightController.text.isNotEmpty ? double.parse(_heightController.text) : null,
        'bmi': bmi?.toStringAsFixed(1),
        'symptoms': _symptomsController.text.trim().isNotEmpty ? _symptomsController.text.trim() : null,
        'medicalHistory': _historyController.text.trim().isNotEmpty ? _historyController.text.trim() : null,
      };

      final patientInfo = {
        'patientId': widget.patientId,
        'name': widget.patientName,
        'doctorId': widget.doctorId,
      };

      final result = await AIService.generateBodyCheckReport(
        vitalData: vitalData,
        patientInfo: patientInfo,
      );

      if (result['success']) {
        setState(() {
          _generatedReport = result['report'];
          _reportId = result['reportId'];
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Report generated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generatePDF() async {
    if (_generatedReport == null) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          // Header
          pw.Header(
            level: 0,
            child: pw.Text(
              'AI Body Check Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),

          pw.SizedBox(height: 20),

          // Patient Info
          pw.Text('Patient: ${_generatedReport!.patientName}', style: const pw.TextStyle(fontSize: 14)),
          pw.Text('Patient ID: ${_generatedReport!.patientId}', style: const pw.TextStyle(fontSize: 14)),
          pw.Text('Date: ${_generatedReport!.date.toString().split('.')[0]}', style: const pw.TextStyle(fontSize: 14)),

          pw.SizedBox(height: 20),

          // Risk Level
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _getRiskColor(_generatedReport!.overallRiskLevel),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Text(
              'Overall Risk Level: ${_generatedReport!.overallRiskLevel.toUpperCase()}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            ),
          ),

          pw.SizedBox(height: 20),

          // Summary
          pw.Text('Summary:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(_generatedReport!.summary),

          pw.SizedBox(height: 20),

          // Risk Alerts
          if (_generatedReport!.riskAlerts.isNotEmpty) ...[
            pw.Text('⚠️ Risk Alerts:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            ...(_generatedReport!.riskAlerts.map((alert) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.red),
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(alert.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Severity: ${alert.severity}'),
                  pw.Text(alert.description),
                  pw.Text('Action: ${alert.recommendedAction}'),
                ],
              ),
            ))),
          ],

          pw.SizedBox(height: 20),

          // Recommendations
          pw.Text('Recommendations:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          ...(_generatedReport!.recommendations.map((rec) => pw.Bullet(text: rec))),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  PdfColor _getRiskColor(String riskLevel) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Body Check Report'),
        backgroundColor: const Color(0xFF00C9B8),
      ),
      body: _generatedReport == null ? _buildInputForm() : _buildReportView(),
    );
  }

  Widget _buildInputForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient: ${widget.patientName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            const Text('Enter Vital Signs:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _systolicController,
                    decoration: const InputDecoration(
                      labelText: 'Systolic BP (mmHg)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _diastolicController,
                    decoration: const InputDecoration(
                      labelText: 'Diastolic BP (mmHg)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _heartRateController,
              decoration: const InputDecoration(
                labelText: 'Heart Rate (bpm)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _temperatureController,
              decoration: const InputDecoration(
                labelText: 'Temperature (°C)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _spo2Controller,
              decoration: const InputDecoration(
                labelText: 'SpO2 (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _respiratoryRateController,
              decoration: const InputDecoration(
                labelText: 'Respiratory Rate (breaths/min)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _bloodSugarController,
              decoration: const InputDecoration(
                labelText: 'Blood Sugar (mg/dL)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _heightController,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _symptomsController,
              decoration: const InputDecoration(
                labelText: 'Symptoms (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _historyController,
              decoration: const InputDecoration(
                labelText: 'Medical History (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGenerating ? null : _generateReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C9B8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isGenerating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('🤖 Generate AI Report', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _generatedReport!.patientName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text('ID: ${_generatedReport!.patientId}'),
                    Text(_generatedReport!.date.toString().split('.')[0]),
                  ],
                ),
              ),
              RiskBadge(risk: _generatedReport!.overallRiskLevel),
            ],
          ),
          const SizedBox(height: 20),

          // Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(_generatedReport!.summary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Risk Alerts
          if (_generatedReport!.riskAlerts.isNotEmpty) ...[
            const Text('⚠️ Risk Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 10),
            ...(_generatedReport!.riskAlerts.map((alert) => Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(alert.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(alert.severity.toUpperCase()),
                          backgroundColor: _getRiskColorUI(alert.severity),
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(alert.description),
                    const SizedBox(height: 5),
                    Text('Action: ${alert.recommendedAction}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ))),
            const SizedBox(height: 16),
          ],

          // Recommendations
          const Text('Recommendations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...(_generatedReport!.recommendations.map((rec) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(child: Text(rec)),
              ],
            ),
          ))),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generatePDF,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _generatedReport = null;
                      _reportId = null;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('New Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C9B8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}