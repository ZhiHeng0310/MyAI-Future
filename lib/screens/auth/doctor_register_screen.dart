import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/cl_button.dart' as clButton;
import '../../widgets/cl_text_field.dart';

class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});

  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen> {
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _idCtrl     = TextEditingController(); // Doctor ID / licence
  final _specCtrl   = TextEditingController(); // Specialization
  final _codeCtrl   = TextEditingController(); // Clinic registration code
  bool _obscure     = true;
  bool _obscureCode = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _idCtrl.dispose();
    _specCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty ||
        _idCtrl.text.trim().isEmpty ||
        _codeCtrl.text.trim().isEmpty) {
      return;
    }
    await context.read<AuthProvider>().registerDoctor(
      email:          _emailCtrl.text.trim(),
      password:       _passCtrl.text,
      name:           _nameCtrl.text.trim(),
      doctorId:       _idCtrl.text.trim(),
      specialization: _specCtrl.text.trim().isEmpty
          ? null
          : _specCtrl.text.trim(),
      clinicCode:     _codeCtrl.text.trim(),
    );
    // AuthWrapper handles routing on success.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Registration')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        const Color(0xFF6C63FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:       Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.medical_services_rounded,
                        color: Color(0xFF6C63FF), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Doctor Account',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6C63FF))),
                          Text(
                            'A valid clinic registration code is required.',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: const Color(0xFF667085)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              clButton.ClTextField(
                controller: _nameCtrl,
                label:      'Full Name',
                hint:       'Dr. Ahmad bin Abdullah',
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller:   _emailCtrl,
                label:        'Email',
                hint:         'doctor@hospital.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon:   Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller:  _passCtrl,
                label:       'Password',
                hint:        'At least 6 characters',
                obscureText: _obscure,
                prefixIcon:  Icons.lock_outline_rounded,
                suffixIcon:  _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onSuffixTap: () => setState(() => _obscure = !_obscure),
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller: _idCtrl,
                label:      'Doctor ID / Licence Number',
                hint:       'MMC-12345',
                prefixIcon: Icons.badge_outlined,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller: _specCtrl,
                label:      'Specialization (optional)',
                hint:       'General Practitioner',
                prefixIcon: Icons.local_hospital_outlined,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller:  _codeCtrl,
                label:       'Clinic Registration Code',
                hint:        'Enter code provided by clinic admin',
                obscureText: _obscureCode,
                prefixIcon:  Icons.vpn_key_outlined,
                suffixIcon:  _obscureCode
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onSuffixTap: () =>
                    setState(() => _obscureCode = !_obscureCode),
              ),

              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(auth.error!,
                      style: TextStyle(
                          color: Colors.red.shade700, fontSize: 13)),
                ),
              ],

              const SizedBox(height: 32),
              clButton.ClButton(
                label:     'Register as Doctor',
                loading:   auth.loading,
                onPressed: _register,
                color:     const Color(0xFF6C63FF),
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Back to Sign In',
                    style: TextStyle(
                        color: Color(0xFF667085), fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}