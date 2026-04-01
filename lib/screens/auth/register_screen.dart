import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/cl_button.dart';
import '../../widgets/cl_text_field.dart' as clButton;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty) {
      return;
    }
    // Just call registerPatient — AuthWrapper handles routing automatically.
    await context.read<AuthProvider>().registerPatient(
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
      name:     _nameCtrl.text.trim(),
      phone:    _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join CareLoop',
                  style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 8),
              Text('Your intelligent health companion',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 36),

              clButton.ClTextField(
                controller: _nameCtrl,
                label:      'Full Name',
                hint:       'Ahmad bin Abdullah',
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller:   _emailCtrl,
                label:        'Email',
                hint:         'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon:   Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              clButton.ClTextField(
                controller:   _phoneCtrl,
                label:        'Phone (optional)',
                hint:         '+60 12-345 6789',
                keyboardType: TextInputType.phone,
                prefixIcon:   Icons.phone_outlined,
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
              ClButton(
                label:     'Create Account',
                loading:   auth.loading,
                onPressed: _register,
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Already have an account? Sign In',
                    style:
                    TextStyle(color: Color(0xFF00C896), fontSize: 14),
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
