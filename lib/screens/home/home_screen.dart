import 'package:flutter/material.dart' hide debugPrint;
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/appointment_provider.dart';

import '../../services/inbox_service.dart';

import '../chat/chat_screen.dart';
import 'dashboard_tab.dart';
import '../queue/queue_screen.dart';
import '../medications/medication_screen.dart';
import '../appointment/appointment_screen.dart';

import '../../widgets/inbox_icon.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _currentIndex;
  bool _initialized  = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final patient = Provider.of<AuthProvider>(context).patient;

    if (patient != null && !_initialized) {
      _initialized = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        debugPrint('🏠 HomeScreen: Initializing services for patient ${patient.id}');

        // Start inbox listener
        final inboxService = context.read<InboxService>();
        debugPrint('🏠 HomeScreen: Starting InboxService listener');
        inboxService.startListening(patient.id);
        debugPrint('🏠 HomeScreen: InboxService has ${inboxService.notifications.length} notifications');

        final queueProv       = context.read<QueueProvider>();
        final chatProv        = context.read<ChatProvider>();
        final medProv         = context.read<MedicationProvider>();
        final appointmentProv = context.read<AppointmentProvider>();

        queueProv.startListening(patient.id);
        medProv.startListening(patient.id, patient: patient);

        // Issue 5+6 fix: start appointment provider early so stream is active
        // This ensures booked appointments immediately appear in the Appointments tab
        appointmentProv.startListening(patient.id);

        chatProv.setQueueProvider(queueProv);
        // Issue 5 fix: pass AppointmentProvider to ChatProvider so
        // after AI books an appointment it refreshes the stream
        chatProv.setAppointmentProvider(appointmentProv);
        chatProv.initSession(patient);

        debugPrint('🏠 HomeScreen: All services initialized');
      });
    }
  }

  static const _navItems = [
    NavigationDestination(
      icon:         Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label:        'Home',
    ),
    NavigationDestination(
      icon:         Icon(Icons.queue_outlined),
      selectedIcon: Icon(Icons.queue_rounded),
      label:        'Queue',
    ),
    NavigationDestination(
      icon:         Icon(Icons.chat_bubble_outline_rounded),
      selectedIcon: Icon(Icons.chat_bubble_rounded),
      label:        'AI Care',
    ),
    NavigationDestination(
      icon:         Icon(Icons.medication_outlined),
      selectedIcon: Icon(Icons.medication_rounded),
      label:        'Meds',
    ),
    NavigationDestination(
      icon:         Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month_rounded),
      label:        'Appointments',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const screens = [
      DashboardTab(),
      QueueScreen(),
      ChatScreen(),
      MedicationScreen(),
      AppointmentsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('CareLoop'),
        backgroundColor: const Color(0xFF00C896),
        foregroundColor: Colors.white,
        actions: [
          const InboxIconAnimated(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex:         _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations:          _navItems,
        backgroundColor:       Colors.white,
        indicatorColor:        const Color(0xFF00C896).withOpacity(0.15),
        shadowColor:           Colors.black12,
        elevation:             8,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}