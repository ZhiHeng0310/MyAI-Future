import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pure display widget — shows the CareLoop branding while Firebase/Auth
/// is initialising. All routing decisions are made by AuthWrapper in main.dart.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Center(
        child: Column(
          mainAxisAlignment: MFainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF00C896),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C896).withOpacity(0.4),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: Colors.white, size: 44),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut)
                .then()
                .shimmer(duration: 800.ms, color: Colors.white24),

            const SizedBox(height: 24),

            Text(
              'CareLoop',
              style: GoogleFonts.poppins(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: 0.3),

            const SizedBox(height: 8),

            Text(
              'Intelligent Care, Continuously',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: Colors.white54, letterSpacing: 0.3),
            ).animate(delay: 500.ms).fadeIn(duration: 500.ms),

            const SizedBox(height: 60),

            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xFF00C896).withOpacity(0.6),
              ),
            ).animate(delay: 800.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}