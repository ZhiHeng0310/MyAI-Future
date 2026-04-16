import 'package:flutter/material.dart';
import 'ai_body_check_screen.dart';
import 'ai_report_summarizer_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/patient_model.dart';

class DoctorAIScreen extends StatelessWidget {
  const DoctorAIScreen({super.key});

  Future<void> _showPatientSelector(BuildContext context, String doctorId) async {
    try {
      // Fetch patients from Firestore
      final patientsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .limit(50)
          .get();

      if (!context.mounted) return;

      final patients = patientsSnapshot.docs
          .map((doc) {
        try {
          return PatientModel.fromFirestore(doc);
        } catch (e) {
          print('Error parsing patient: $e');
          return null;
        }
      })
          .where((p) => p != null)
          .cast<PatientModel>()
          .toList();

      if (patients.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No patients found. Please add patients first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Show patient selection dialog
      final selectedPatient = await showDialog<PatientModel>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Patient'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF00C9B8),
                    child: Text(
                      patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(patient.name),
                  subtitle: Text('ID: ${patient.id}'),
                  onTap: () => Navigator.pop(context, patient),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedPatient != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AIBodyCheckScreen(
              patientId: selectedPatient.id,
              patientName: selectedPatient.name,
              doctorId: doctorId,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error loading patients: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading patients: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final currentDoctorId = doctor?.doctorId ?? '';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              '🤖 AI-Powered Medical Tools',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'Generate comprehensive reports and patient-friendly summaries with AI risk detection',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                // AI Body Check
                _buildFeatureCard(
                  context,
                  icon: Icons.medical_services,
                  title: 'AI Body Check',
                  subtitle: 'Generate Reports',
                  color: const Color(0xFF00C9B8),
                  onTap: () => _showPatientSelector(context, currentDoctorId),
                ),

                // AI Summarizer
                _buildFeatureCard(
                  context,
                  icon: Icons.summarize,
                  title: 'AI Summarizer',
                  subtitle: 'Send to Patients',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AIReportSummarizerScreen(
                          doctorId: currentDoctorId,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}