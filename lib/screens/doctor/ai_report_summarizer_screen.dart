// screens/doctor/ai_report_summarizer_screen.dart
// AI Report Summarizer + Send to Patient with Risk Detection

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/ai_service.dart';
import '../../models/ai_summary_model.dart';
import '../../models/patient_model.dart';
import '../../widgets/risk_badge.dart';

class AIReportSummarizerScreen extends StatefulWidget {
  final String? doctorId;

  const AIReportSummarizerScreen({
    Key? key,
    this.doctorId,
  }) : super(key: key);

  @override
  State<AIReportSummarizerScreen> createState() => _AIReportSummarizerScreenState();
}

class _AIReportSummarizerScreenState extends State<AIReportSummarizerScreen> {
  String? _selectedReportId;
  Map<String, dynamic>? _selectedReportData;
  String? _selectedPatientId;
  String? _selectedPatientName;

  bool _isLoadingReports = false;
  bool _isGeneratingSummary = false;
  bool _isSending = false;

  AISummary? _generatedSummary;
  String? _summaryId;

  List<Map<String, dynamic>> _reports = [];
  List<PatientModel> _patients = [];

  @override
  void initState() {
    super.initState();
    _loadRecentReports();
    _loadPatients();
  }

  Future<void> _loadRecentReports() async {
    setState(() => _isLoadingReports = true);

    try {
      final reportsSnapshot = await FirebaseFirestore.instance
          .collection('medical_reports')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      setState(() {
        _reports = reportsSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'reportId': data['reportId'],
            'patientId': data['patientId'],
            'patientName': data['patientName'],
            'createdAt': data['createdAt'],
            'reportData': data['reportData'],
            'reportType': data['reportType'] ?? 'body_check',
          };
        }).toList();
      });
    } catch (e) {
      print('❌ Error loading reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading reports: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingReports = false);
    }
  }

  Future<void> _loadPatients() async {
    try {
      final patientsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .limit(100)
          .get();

      setState(() {
        _patients = patientsSnapshot.docs
            .map((doc) => PatientModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      print('❌ Error loading patient: $e');
    }
  }

  Future<void> _generateSummary() async {
    if (_selectedReportData == null || _selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a report first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingSummary = true);

    try {
      final patientInfo = {
        'patientId': _selectedPatientId,
        'name': _selectedPatientName ?? 'Unknown Patient',
      };

      final result = await AIService.summarizeReport(
        reportId: _selectedReportId,
        reportData: _selectedReportData!,
        patientInfo: patientInfo,
      );

      if (result['success']) {
        setState(() {
          _generatedSummary = result['summary'];
          _summaryId = result['summaryId'];
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Summary generated successfully!'),
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
      setState(() => _isGeneratingSummary = false);
    }
  }

  Future<void> _sendToPatient() async {
    if (_generatedSummary == null || _summaryId == null || _selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please generate a summary first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show patient selection dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Summary to Patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: $_selectedPatientName'),
            const SizedBox(height: 10),
            Text('Risk Level: ${_generatedSummary!.riskLevel.toUpperCase()}'),
            const SizedBox(height: 10),
            const Text('This summary will be sent to the patient\'s inbox.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9B8)),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      final result = await AIService.sendSummaryToPatient(
        summaryId: _summaryId!,
        patientId: _selectedPatientId!,
        doctorId: widget.doctorId,
        summaryData: _generatedSummary!.toJson(),
      );

      if (result['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Summary sent to patient successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Reset form
          setState(() {
            _selectedReportId = null;
            _selectedReportData = null;
            _selectedPatientId = null;
            _selectedPatientName = null;
            _generatedSummary = null;
            _summaryId = null;
          });
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
      setState(() => _isSending = false);
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

  String _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'good':
        return '✓';
      case 'needs attention':
        return '⚠️';
      case 'concerning':
        return '❌';
      default:
        return '•';
    }
  }

  Color _getStatusColor(String status) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Report Summarizer'),
        backgroundColor: const Color(0xFF00C9B8),
      ),
      body: _generatedSummary == null ? _buildReportSelection() : _buildSummaryView(),
    );
  }

  Widget _buildReportSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1. Select a Report to Summarize',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (_isLoadingReports)
            const Center(child: CircularProgressIndicator())
          else if (_reports.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No reports available. Generate a body check report first.'),
              ),
            )
          else
            ..._reports.map((report) => Card(
              color: _selectedReportId == report['id'] ? Colors.blue.shade50 : null,
              child: ListTile(
                leading: const Icon(Icons.description, color: Color(0xFF00C9B8)),
                title: Text(report['patientName'] ?? 'Unknown Patient'),
                subtitle: Text(
                  'Report ID: ${report['reportId']}\n${report['createdAt'] ?? 'Unknown date'}',
                ),
                trailing: _selectedReportId == report['id']
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedReportId = report['id'];
                    _selectedReportData = report['reportData'];
                    _selectedPatientId = report['patientId'];
                    _selectedPatientName = report['patientName'];
                  });
                },
              ),
            )),

          const SizedBox(height: 20),

          if (_selectedReportId != null) ...[
            const Text(
              '2. Generate Patient-Friendly Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected: $_selectedPatientName'),
                    Text('Patient ID: $_selectedPatientId'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isGeneratingSummary ? null : _generateSummary,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C9B8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isGeneratingSummary
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('🤖 Generate AI Summary', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryView() {
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
                      _generatedSummary!.patientName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text('Patient-Friendly Summary'),
                    Text(_generatedSummary!.date.toString().split('.')[0]),
                  ],
                ),
              ),
              RiskBadge(risk: _generatedSummary!.riskLevel),
            ],
          ),
          const SizedBox(height: 20),

          // Overall Status
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Overall Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(_generatedSummary!.overallStatus, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Risk Explanation
          if (_generatedSummary!.riskExplanation.isNotEmpty) ...[
            Card(
              color: _getRiskColorUI(_generatedSummary!.riskLevel).withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: _getRiskColorUI(_generatedSummary!.riskLevel)),
                        const SizedBox(width: 8),
                        const Text('About Your Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_generatedSummary!.riskExplanation),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Key Findings
          const Text('Key Findings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...(_generatedSummary!.keyFindings.map((finding) => Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getStatusColor(finding.status),
                child: Text(finding.icon, style: const TextStyle(color: Colors.white)),
              ),
              title: Text(finding.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(finding.explanation),
            ),
          ))),
          const SizedBox(height: 16),

          // What This Means
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What This Means', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(_generatedSummary!.whatThisMeans),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Next Steps
          const Text('Next Steps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...(_generatedSummary!.nextSteps.map((step) => Card(
            color: step.urgency == 'immediate' ? Colors.red.shade50 : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(step.action, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      if (step.urgency != 'routine')
                        Chip(
                          label: Text(step.urgency.toUpperCase()),
                          backgroundColor: step.urgency == 'immediate' ? Colors.red : Colors.orange,
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(step.reason),
                ],
              ),
            ),
          ))),
          const SizedBox(height: 16),

          // Positive Notes
          if (_generatedSummary!.positiveNotes.isNotEmpty) ...[
            const Text('✨ Positive Notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 10),
            ...(_generatedSummary!.positiveNotes.map((note) => Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(child: Text(note)),
                  ],
                ),
              ),
            ))),
            const SizedBox(height: 16),
          ],

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendToPatient,
                  icon: _isSending
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : const Icon(Icons.send),
                  label: const Text('Send to Patient'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C9B8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedReportId = null;
                      _selectedReportData = null;
                      _selectedPatientId = null;
                      _selectedPatientName = null;
                      _generatedSummary = null;
                      _summaryId = null;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('New Summary'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
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