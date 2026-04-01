import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/cl_button.dart';
import '../../widgets/cl_text_field.dart' as widgets;
import '../home/home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('CareLoop', style: Theme.of(context).textTheme.displayMedium),
                ],
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.2),

              const SizedBox(height: 48),

              Text('Welcome back', style: Theme.of(context).textTheme.displayLarge)
                  .animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 8),

              Text('Sign in to continue your care journey',
                      style: Theme.of(context).textTheme.bodyLarge)
                  .animate(delay: 150.ms).fadeIn(),

              const SizedBox(height: 40),

              // Fields
              widgets.ClTextField(
                controller: _emailCtrl,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
              ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 16),

              widgets.ClTextField(
                controller: _passCtrl,
                label: 'Password',
                hint: '••••••••',
                obscureText: _obscure,
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onSuffixTap: () => setState(() => _obscure = !_obscure),
              ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),

              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(auth.error!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              ClButton(
                label: 'Sign In',
                loading: auth.loading,
                onPressed: _login,
              ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: GoogleFonts.dmSans(
                          color: const Color(0xFF667085), fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Register',
                          style: GoogleFonts.dmSans(
                            color: const Color(0xFF00C896),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate(delay: 350.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}
