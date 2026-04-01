import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/cl_button.dart';
import '../../widgets/cl_text_field.dart' as cl;
import 'register_screen.dart';
import 'doctor_register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool    _obscure      = true;
  bool    _seeding      = false;
  String? _seedMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    await context.read<AuthProvider>().signIn(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );
    // AuthWrapper handles routing automatically — no Navigator needed here
  }

  // ── DEBUG: one-tap test doctor creator ──────────────────────────────────
  // Bug fix: must write Firestore doc WHILE signed in (before signOut),
  // otherwise the write happens as unauthenticated → PERMISSION_DENIED.
  Future<void> _seedTestDoctor() async {
    setState(() { _seeding = true; _seedMessage = null; });

    const email    = 'doctor@careloop.test';
    const password = 'Doctor@123';
    const name     = 'Dr. Test Account';
    const doctorId = 'MMC-00001';

    try {
      String uid;

      try {
        // Try signing in (account may already exist)
        final cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        uid = cred.user!.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          // Create fresh account
          final cred = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
              email: email, password: password);
          uid = cred.user!.uid;
        } else {
          rethrow;
        }
      }

      // ✅ Write to Firestore WHILE authenticated (before signing out)
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .set({
        'name':           name,
        'email':          email,
        'doctorId':       doctorId,
        'specialization': 'General Practitioner',
        'clinicId':       'clinic_main',
        'role':           'doctor',
      });

      // Now sign out — Firestore write already completed above
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        setState(() {
          _seedMessage = '✅ Doctor account ready!\n'
              'Email:    $email\n'
              'Password: $password';
        });
        _emailCtrl.text = email;
        _passCtrl.text  = password;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _seedMessage = '❌ Auth error: ${e.code} — ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _seedMessage = '❌ Seed failed: $e');
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
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

              // Logo row
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        const Color(0xFF00C896),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('CareLoop',
                      style: Theme.of(context).textTheme.displayMedium),
                ],
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.2),

              const SizedBox(height: 48),

              Text('Welcome back',
                  style: Theme.of(context).textTheme.displayLarge)
                  .animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 8),
              Text('Sign in to continue your care journey',
                  style: Theme.of(context).textTheme.bodyLarge)
                  .animate(delay: 150.ms).fadeIn(),

              const SizedBox(height: 40),

              cl.ClTextField(
                controller:   _emailCtrl,
                label:        'Email address',
                hint:         'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon:   Icons.email_outlined,
              ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 16),

              cl.ClTextField(
                controller:  _passCtrl,
                label:       'Password',
                hint:        '••••••••',
                obscureText: _obscure,
                prefixIcon:  Icons.lock_outline_rounded,
                suffixIcon:  _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onSuffixTap: () => setState(() => _obscure = !_obscure),
              ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),

              if (auth.error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: auth.error!),
              ],

              const SizedBox(height: 32),

              ClButton(
                label:     'Sign In',
                loading:   auth.loading,
                onPressed: _login,
              ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RegisterScreen())),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: GoogleFonts.dmSans(
                          color: const Color(0xFF667085), fontSize: 14),
                      children: [
                        TextSpan(
                          text:  'Register as Patient',
                          style: GoogleFonts.dmSans(
                              color:      const Color(0xFF00C896),
                              fontWeight: FontWeight.w600,
                              fontSize:   14),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate(delay: 350.ms).fadeIn(),

              const SizedBox(height: 12),

              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DoctorRegisterScreen())),
                  child: RichText(
                    text: TextSpan(
                      text: 'Are you a doctor? ',
                      style: GoogleFonts.dmSans(
                          color: const Color(0xFF667085), fontSize: 14),
                      children: [
                        TextSpan(
                          text:  'Register here',
                          style: GoogleFonts.dmSans(
                              color:      const Color(0xFF6C63FF),
                              fontWeight: FontWeight.w600,
                              fontSize:   14),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate(delay: 380.ms).fadeIn(),

              // ── DEBUG ONLY — stripped from release builds ────────────────
              if (kDebugMode) ...[
                const SizedBox(height: 36),
                const Divider(),
                const SizedBox(height: 8),
                Center(
                  child: Text('🛠 DEBUG — Test Accounts',
                      style: GoogleFonts.dmSans(
                          fontSize:   11,
                          color:      const Color(0xFF667085),
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _seeding
                        ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF6C63FF)))
                        : const Icon(Icons.medical_services_rounded,
                        size: 16),
                    label: Text(_seeding
                        ? 'Creating doctor account…'
                        : 'Create Test Doctor Account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6C63FF),
                      side: const BorderSide(color: Color(0xFF6C63FF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _seeding ? null : _seedTestDoctor,
                  ),
                ),

                if (_seedMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _seedMessage!.startsWith('✅')
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _seedMessage!.startsWith('✅')
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Text(
                      _seedMessage!,
                      style: TextStyle(
                        fontSize:   12,
                        color: _seedMessage!.startsWith('✅')
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        height:     1.6,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (_seedMessage!.startsWith('✅')) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                        ),
                        child:
                        const Text('Sign in as Doctor now →'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
              ],
              // ── end debug ────────────────────────────────────────────────
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: Colors.red.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}