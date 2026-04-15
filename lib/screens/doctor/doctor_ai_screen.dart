import 'package:flutter/material.dart';
import 'ai_body_check_screen.dart';
import 'ai_report_summarizer_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class DoctorAIScreen extends StatelessWidget {
  const DoctorAIScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final currentDoctorId = doctor?.doctorId ?? '';

    return Padding(
      padding: const EdgeInsets.all(16),
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AIBodyCheckScreen(
                    patientId: 'selected_patient_id',
                    patientName: 'Selected Patient',
                    doctorId: currentDoctorId,
                  ),
                ),
              );
            },
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