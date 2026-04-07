import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/auth_provider.dart';
import '../../providers/appointment_provider.dart';
import '../../models/appointment_model.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final patient = context.read<AuthProvider>().patient;
      if (patient != null) {
        context.read<AppointmentProvider>().startListening(patient.id);
      }
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Appointments',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
          labelColor:            const Color(0xFF00C896),
          unselectedLabelColor:  const Color(0xFF667085),
          indicatorColor:        const Color(0xFF00C896),
          labelStyle:            const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Consumer<AppointmentProvider>(
        builder: (ctx, provider, _) {
          final all      = provider.myAppointments;
          final now      = DateTime.now();
          final upcoming = all
              .where((a) =>
          a.date.isAfter(now) &&
              a.status != AppointmentStatus.cancelled)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          final past = all
              .where((a) =>
          a.date.isBefore(now) ||
              a.status == AppointmentStatus.cancelled ||
              a.status == AppointmentStatus.completed)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          return TabBarView(
            controller: _tabCtrl,
            children: [
              _AppointmentList(
                appointments: upcoming,
                emptyTitle:   'No upcoming appointments',
                emptySubtitle: 'Ask CareLoop AI to book one for you!',
                emptyIcon:    Icons.calendar_today_outlined,
              ),
              _AppointmentList(
                appointments: past,
                emptyTitle:   'No past appointments',
                emptySubtitle: 'Your appointment history will appear here.',
                emptyIcon:    Icons.history_rounded,
                isPast:       true,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Appointment List ─────────────────────────────────────────────────────────

class _AppointmentList extends StatelessWidget {
  final List<AppointmentSlot> appointments;
  final String   emptyTitle;
  final String   emptySubtitle;
  final IconData emptyIcon;
  final bool     isPast;

  const _AppointmentList({
    required this.appointments,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF00C896).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(emptyIcon, color: const Color(0xFF00C896), size: 36),
            ),
            const SizedBox(height: 16),
            Text(emptyTitle,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(emptySubtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      color: const Color(0xFF667085), fontSize: 14)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding:     const EdgeInsets.all(16),
      itemCount:   appointments.length,
      itemBuilder: (ctx, i) => _AppointmentCard(
        appt:   appointments[i],
        isPast: isPast,
      )
          .animate(delay: Duration(milliseconds: i * 60))
          .fadeIn()
          .slideY(begin: 0.1),
    );
  }
}

// ─── Appointment Card ─────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  final AppointmentSlot appt;
  final bool            isPast;

  const _AppointmentCard({required this.appt, required this.isPast});

  Color get _statusColor {
    switch (appt.status) {
      case AppointmentStatus.confirmed:  return const Color(0xFF00C896);
      case AppointmentStatus.pending:    return Colors.orange;
      case AppointmentStatus.cancelled:  return Colors.red;
      case AppointmentStatus.completed:  return const Color(0xFF667085);
    }
  }

  String get _statusLabel {
    switch (appt.status) {
      case AppointmentStatus.confirmed:  return 'Confirmed ✓';
      case AppointmentStatus.pending:    return 'Pending';
      case AppointmentStatus.cancelled:  return 'Cancelled';
      case AppointmentStatus.completed:  return 'Completed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(appt.date);
    final isTomorrow = _isTomorrow(appt.date);
    final dateNote = isToday ? '🔴 Today' : isTomorrow ? '🟡 Tomorrow' : null;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pushNamed(
          context,
          "/appointment-details",
          arguments: appt.id,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPast
                ? const Color(0xFFE4E7EC)
                : _statusColor.withOpacity(0.3),
            width: isPast ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date box
              Container(
                width: 56, height: 64,
                decoration: BoxDecoration(
                  color: isPast
                      ? const Color(0xFFF2F4F7)
                      : _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _monthShort(appt.date),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isPast
                              ? const Color(0xFF667085)
                              : _statusColor),
                    ),
                    Text(
                      '${appt.date.day}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isPast
                              ? const Color(0xFF344054)
                              : _statusColor),
                    ),
                    Text(
                      '${appt.date.year}',
                      style: TextStyle(
                          fontSize: 9,
                          color: isPast
                              ? const Color(0xFF667085)
                              : _statusColor),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Dr. ${appt.doctorName}',
                              style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: const Color(0xFF0D1B2A))),
                        ),
                        if (dateNote != null)
                          Text(dateNote,
                              style: const TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 13, color: Color(0xFF667085)),
                        const SizedBox(width: 4),
                        Text(appt.timeSlot,
                            style: GoogleFonts.dmSans(
                                fontSize: 13, color: const Color(0xFF344054))),
                      ],
                    ),

                    const SizedBox(height: 4),

                    if (appt.symptoms.isNotEmpty)
                      Wrap(
                        spacing: 4, runSpacing: 4,
                        children: appt.symptoms.take(3).map((s) =>
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(s,
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFF344054))),
                            )).toList(),
                      ),

                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_statusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthShort(DateTime d) {
    const m = ['JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC'];
    return m[d.month - 1];
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isTomorrow(DateTime d) {
    final t = DateTime.now().add(const Duration(days: 1));
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }
}