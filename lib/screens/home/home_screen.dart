import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/chat_provider.dart';
import 'dashboard_tab.dart';
import '../queue/queue_screen.dart';
import '../chat/chat_screen.dart';
import '../medications/medication_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    final auth = context.read<AuthProvider>();
    final patient = auth.patient;
    if (patient == null) return;

    context.read<QueueProvider>().startListening();
    context.read<MedicationProvider>().startListening(patient.id);
    context.read<ChatProvider>().initSession(patient);
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
    final screens = [
      const DashboardTab(),
      const QueueScreen(),
      const ChatScreen(),
      const MedicationScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
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
