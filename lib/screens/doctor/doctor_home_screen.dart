import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/doctor_chat_provider.dart';
import 'doctor_queue_screen.dart';
import 'doctor_alerts_screen.dart';
import 'doctor_chat_screen.dart';
import 'doctor_patients_screen.dart';
import 'doctor_ai_screen.dart';
import 'ai_body_check_screen.dart';
import 'ai_report_summarizer_screen.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  int  _index       = 0;
  bool _chatInited  = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final doctor = Provider.of<AuthProvider>(context).doctor;
    if (doctor != null && !_chatInited) {
      _chatInited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<DoctorChatProvider>().initSession(doctor);
      });
    }
  }

  static const _navItems = [
    NavigationDestination(
      icon:         Icon(Icons.queue_outlined),
      selectedIcon: Icon(Icons.queue_rounded),
      label:        'Queue',
    ),
    NavigationDestination(
      icon:         Icon(Icons.people_outline_rounded),
      selectedIcon: Icon(Icons.people_rounded),
      label:        'Patients',
    ),
    NavigationDestination(
      icon:         Icon(Icons.notifications_outlined),
      selectedIcon: Icon(Icons.notifications_rounded),
      label:        'Alerts',
    ),
    NavigationDestination(
      icon:         Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy_rounded),
      label:        'AI Care',
    ),
    NavigationDestination(
      icon: Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy_rounded),
      label: 'AI Tools',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final name   = doctor?.name.split(' ').last ?? 'Doctor';

    final screens = [
      DoctorQueueScreen(clinicId: doctor?.clinicId ?? 'clinic_main'),
      const DoctorPatientsScreen(),
      const DoctorAlertsScreen(),
      const DoctorChatScreen(),
      const DoctorAIScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color:        const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medical_services_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dr. $name',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (doctor?.doctorId != null)
                  Text(doctor!.doctorId,
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: const Color(0xFF667085))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:    const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex:         _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations:          _navItems,
        backgroundColor:       Colors.white,
        indicatorColor:        const Color(0xFF6C63FF).withOpacity(0.15),
        elevation:             8,
        shadowColor:           Colors.black12,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}