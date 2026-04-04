import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/chat_provider.dart';

import '../ai_chat_screen_gemini.dart';
import 'dashboard_tab.dart';
import '../queue/queue_screen.dart';
import '../chat/chat_screen.dart';
import '../medications/medication_screen.dart';

import '../../widgets/inbox_icon.dart';
import '../../widgets/upcoming_appointments_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final patient = Provider.of<AuthProvider>(context).patient;

    if (patient != null && !_initialized) {
      _initialized = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final queueProv = context.read<QueueProvider>();
        final chatProv = context.read<ChatProvider>();
        final medProv = context.read<MedicationProvider>();

        queueProv.startListening(patient.id);
        medProv.startListening(patient.id, patient: patient);

        chatProv.setQueueProvider(queueProv);
        chatProv.initSession(patient);
      });
    }
  }

  static const _navItems = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.queue_outlined),
      selectedIcon: Icon(Icons.queue_rounded),
      label: 'Queue',
    ),
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline_rounded),
      selectedIcon: Icon(Icons.chat_bubble_rounded),
      label: 'AI Care',
    ),
    NavigationDestination(
      icon: Icon(Icons.medication_outlined),
      selectedIcon: Icon(Icons.medication_rounded),
      label: 'Meds',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final patient = context.watch<AuthProvider>().patient;

    final screens = [
      // 🔥 MODIFY ONLY THIS PART
      SingleChildScrollView(
        child: Column(
          children: [
            if (patient != null)
              UpcomingAppointmentsWidget(userId: patient.id),

            const SizedBox(height: 10),

            const DashboardTab(),
          ],
        ),
      ),

      const QueueScreen(),
      Builder(
        builder: (context) {
          final patient = context.watch<AuthProvider>().patient;

          if (patient == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return AIChatScreen(userId: patient.id);
        },
      ),
      const MedicationScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('CareLoop'),
        actions: [
          // ✅ Inbox icon added safely
          const InboxIconAnimated(),

          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // TODO: your logout logic
            },
          ),
        ],
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _navItems,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF00C896).withOpacity(0.15),
        shadowColor: Colors.black12,
        elevation: 8,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}