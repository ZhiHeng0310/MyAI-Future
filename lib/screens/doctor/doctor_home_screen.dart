import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import 'doctor_queue_screen.dart';
import 'doctor_patients_screen.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  int _index = 0;

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
  ];

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final name   = doctor?.name.split(' ').first ?? 'Doctor';

    final screens = [
      DoctorQueueScreen(clinicId: doctor?.clinicId ?? 'clinic_main'),
      const DoctorPatientsScreen(),
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
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              // AuthWrapper navigates back to LoginScreen automatically
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex:          _index,
        onDestinationSelected:  (i) => setState(() => _index = i),
        destinations:           _navItems,
        backgroundColor:        Colors.white,
        indicatorColor:         const Color(0xFF6C63FF).withOpacity(0.15),
        elevation:              8,
        shadowColor:            Colors.black12,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}