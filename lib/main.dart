import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart' as Auth;
import 'providers/queue_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/chat_provider.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/doctor/doctor_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  runApp(const CareLoopApp());
}

class CareLoopApp extends StatelessWidget {
  const CareLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => QueueProvider()),
        ChangeNotifierProvider(create: (_) => MedicationProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: 'CareLoop',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const AuthWrapper(),
      ),
    );
  }

  ThemeData _buildTheme() {
    const brand = Color(0xFF00C896);
    const dark  = Color(0xFF0D1B2A);
    const grey  = Color(0xFF667085);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: brand, brightness: Brightness.light),
      scaffoldBackgroundColor: const Color(0xFFF8FFFE),
      textTheme: GoogleFonts.dmSansTextTheme().copyWith(
        displayLarge: GoogleFonts.poppins(
            fontSize: 32, fontWeight: FontWeight.w700, color: dark),
        displayMedium: GoogleFonts.poppins(
            fontSize: 24, fontWeight: FontWeight.w600, color: dark),
        titleLarge: GoogleFonts.dmSans(
            fontSize: 20, fontWeight: FontWeight.w600, color: dark),
        bodyLarge:  GoogleFonts.dmSans(
            fontSize: 16, color: const Color(0xFF344054)),
        bodyMedium: GoogleFonts.dmSans(fontSize: 14, color: grey),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF8FFFE),
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
            fontSize: 20, fontWeight: FontWeight.w600, color: dark),
        iconTheme: const IconThemeData(color: dark),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F4F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

/// Root navigation controller.
///
/// Flow:
///  • Firebase still loading   → SplashScreen
///  • No user                  → LoginScreen
///  • User logged in, profile  → wait (SplashScreen) until profileLoading=false
///  • Role = doctor            → DoctorHomeScreen
///  • Role = patient           → HomeScreen
///
/// Auth screens (Login/Register) NEVER call Navigator.pushReplacement.
/// They just call provider methods; this widget reacts automatically.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Waiting for Firebase to initialise
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // Not signed in
        if (snapshot.data == null) {
          return const LoginScreen();
        }

        // Signed in — wait for Firestore profile to load
        final auth = context.watch<Auth.AuthProvider>();
        if (auth.profileLoading) {
          return const SplashScreen();
        }

        // Route by role
        if (auth.isDoctor) return const DoctorHomeScreen();
        return const HomeScreen();
      },
    );
  }
}