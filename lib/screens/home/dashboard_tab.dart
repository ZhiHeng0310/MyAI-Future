import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/medication_provider.dart';
import '../../widgets/stat_card.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final queue   = context.watch<QueueProvider>();
    final meds    = context.watch<MedicationProvider>();
    final patient = auth.patient;
    final name    = patient?.name.split(' ').first ?? 'Patient';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            floating:       false,
            pinned:         true,
            backgroundColor: const Color(0xFF0D1B2A),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B2A), Color(0xFF00473E)],
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding:
                    const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_greeting()},',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white60,
                                  fontSize: 14),
                            ),
                            // Sign out — AuthWrapper handles navigation
                            GestureDetector(
                              onTap: () =>
                                  context.read<AuthProvider>().signOut(),
                              child: const Icon(
                                Icons.logout_rounded,
                                color: Colors.white60,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          style: GoogleFonts.poppins(
                            color:      Colors.white,
                            fontSize:   28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (patient?.diagnosis != null)
                          Text(
                            patient!.diagnosis!,
                            style: GoogleFonts.dmSans(
                              color:      const Color(0xFF00C896),
                              fontSize:   13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        icon:     Icons.queue_rounded,
                        label:    'Queue Position',
                        value:    queue.myEntry == null
                            ? '—'
                            : '#${queue.myPosition}',
                        color:    const Color(0xFF6C63FF),
                        sublabel: queue.myEntry == null
                            ? 'Not in queue'
                            : '~${queue.myEntry!.estimatedWaitMinutes} min',
                      ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        icon:     Icons.medication_rounded,
                        label:    'Meds Today',
                        value:    meds.medications.isEmpty
                            ? '0/0'
                            : '${meds.takenToday}/${meds.medications.length}',
                        color:    const Color(0xFF00C896),
                        sublabel: meds.medications.isEmpty
                            ? 'No meds assigned'
                            : meds.adherenceRate == 1.0
                            ? 'All taken ✓'
                            : '${(meds.adherenceRate * 100).round()}% adherence',
                      ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                if (patient?.lastVisit != null)
                  _RecoveryCard(
                      daysSinceVisit: patient!.daysSinceVisit)
                      .animate(delay: 200.ms)
                      .fadeIn()
                      .slideY(begin: 0.2),

                const SizedBox(height: 16),

                if (meds.medications.isNotEmpty) ...[
                  _SectionHeader(title: "Today's Medications"),
                  const SizedBox(height: 12),
                  ...meds.medications.map((med) => _MedTile(
                    med:   med,
                    onLog: (taken) =>
                        context.read<MedicationProvider>()
                            .logDose(med.id, taken),
                  ).animate(delay: 250.ms).fadeIn()),
                ],

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Greeting rules:
  ///  05:00–11:59 → Good morning
  ///  12:00–16:59 → Good afternoon
  ///  17:00–04:59 → Good night
  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    return 'Good night';
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 17, fontWeight: FontWeight.w700));
  }
}

class _RecoveryCard extends StatelessWidget {
  final int daysSinceVisit;
  const _RecoveryCard({required this.daysSinceVisit});

  @override
  Widget build(BuildContext context) {
    final progress = (daysSinceVisit / 14).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFF00A878)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.healing_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('Recovery Progress',
                style: GoogleFonts.dmSans(
                    color:      Colors.white70,
                    fontSize:   13,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 12),
          Text('Day $daysSinceVisit of recovery',
              style: GoogleFonts.poppins(
                  color:      Colors.white,
                  fontSize:   22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value:      progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text('${(progress * 100).round()}% through standard recovery',
              style: GoogleFonts.dmSans(
                  color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MedTile extends StatelessWidget {
  final dynamic med;
  final Function(bool) onLog;
  const _MedTile({required this.med, required this.onLog});

  @override
  Widget build(BuildContext context) {
    final taken = med.isTakenToday as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: taken
                ? const Color(0xFF00C896).withOpacity(0.3)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color:  Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: taken
                  ? const Color(0xFF00C896).withOpacity(0.12)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medication_rounded,
                color: taken
                    ? const Color(0xFF00C896)
                    : const Color(0xFF667085),
                size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF0D1B2A))),
                Text('${med.dosage} · ${med.frequency}',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF667085))),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onLog(!taken),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: taken
                    ? const Color(0xFF00C896)
                    : const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                taken
                    ? Icons.check_rounded
                    : Icons.add_rounded,
                color: taken ? Colors.white : const Color(0xFF667085),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}