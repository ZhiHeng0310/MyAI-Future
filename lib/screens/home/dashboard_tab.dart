import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/medication_provider.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/upcoming_appointments_widget.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final queue   = context.watch<QueueProvider>();
    final meds    = context.watch<MedicationProvider>();
    final patient = auth.patient;
    final name    = patient?.name.split(' ').first ?? 'Patient';

    final waitInt   = queue.myEstimatedWait;          // plain int
    final waitLabel = queue.myEntry == null
        ? 'Not in queue'
        : queue.myPosition <= 1
        ? "You're next!"
        : '~$waitInt min';

    // ── Slot-level medication stats ─────────────────────────────────────────
    final takenSlots = meds.takenSlotsToday;
    final totalSlots = meds.totalSlotsToday;
    final medValue   = totalSlots == 0 ? '0/0' : '$takenSlots/$totalSlots';
    final medSublabel = totalSlots == 0
        ? 'No meds assigned'
        : meds.adherenceRate == 1.0
        ? 'All doses taken ✓'
        : '${(meds.adherenceRate * 100).round()}% doses taken';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Welcome Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D1B2A), Color(0xFF00473E)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_greeting()},',
                    style: GoogleFonts.dmSans(
                        color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 4),
                Text(name,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.w700)),
                if (patient?.diagnosis != null)
                  Text(patient!.diagnosis!,
                      style: GoogleFonts.dmSans(
                          color: const Color(0xFF00C896),
                          fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),

          const SizedBox(height: 20),

          // ── Upcoming Appointments ──
          if (patient != null)
            UpcomingAppointmentsWidget(userId: patient.id),

          const SizedBox(height: 20),

          // Stats row
          Row(children: [
            Expanded(
              child: StatCard(
                icon:     Icons.queue_rounded,
                label:    'Queue Position',
                value:    queue.myEntry == null ? '—' : '#${queue.myPosition}',
                color:    const Color(0xFF6C63FF),
                sublabel: waitLabel,  // plain string, no function ref
              ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon:     Icons.medication_rounded,
                label:    'Doses Today',
                value:    medValue,   // e.g. "1/2" for twice-daily
                color:    const Color(0xFF00C896),
                sublabel: medSublabel,
              ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
            ),
          ]),

          const SizedBox(height: 16),

          if (patient?.lastVisit != null)
            _RecoveryCard(daysSinceVisit: patient!.daysSinceVisit)
                .animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),

          const SizedBox(height: 16),

          if (meds.medications.isNotEmpty) ...[
            Text("Today's Medications",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...meds.medications.map((med) =>
                _MedTile(med: med,
                    onLogSlot: (slot, taken) =>
                        context.read<MedicationProvider>()
                            .logDoseForSlot(med.id, slot, taken),
                    onLogSingle: (taken) =>
                        context.read<MedicationProvider>()
                            .logDose(med.id, taken))
                    .animate(delay: 250.ms).fadeIn()),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5  && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    return 'Good night';
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

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
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.healing_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('Recovery Progress',
                style: GoogleFonts.dmSans(
                    color: Colors.white70, fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 12),
          Text('Day $daysSinceVisit of recovery',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text('${(progress * 100).round()}% through standard recovery',
              style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MedTile extends StatelessWidget {
  final dynamic                med;
  final Function(String, bool) onLogSlot;
  final Function(bool)         onLogSingle;
  const _MedTile({required this.med, required this.onLogSlot, required this.onLogSingle});

  @override
  Widget build(BuildContext context) {
    final reminderTimes = (med.reminderTimes as List).cast<String>();
    final allTaken      = med.isTakenToday as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: allTaken
                ? const Color(0xFF00C896).withOpacity(0.3)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: allTaken
                      ? const Color(0xFF00C896).withOpacity(0.12)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.medication_rounded,
                    color: allTaken
                        ? const Color(0xFF00C896)
                        : const Color(0xFF667085),
                    size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(med.name as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14,
                            color: Color(0xFF0D1B2A))),
                    Text('${med.dosage} · ${med.frequency}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF667085))),
                  ],
                ),
              ),
            ],
          ),

          if (reminderTimes.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Per-slot buttons in a wrap
            Wrap(
              spacing: 8, runSpacing: 8,
              children: reminderTimes.map((time) {
                final taken = med.isTakenForSlot(time) as bool;
                return GestureDetector(
                  onTap: () => onLogSlot(time, !taken),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: taken
                          ? const Color(0xFF00C896)
                          : const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: taken
                            ? const Color(0xFF00C896)
                            : const Color(0xFFD0D5DD),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          taken
                              ? Icons.check_rounded
                              : Icons.access_time_rounded,
                          color: taken
                              ? Colors.white
                              : const Color(0xFF667085),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(time,
                            style: TextStyle(
                                fontSize:   12,
                                fontWeight: FontWeight.w600,
                                color: taken
                                    ? Colors.white
                                    : const Color(0xFF344054))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => onLogSingle(!allTaken),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: allTaken
                      ? const Color(0xFF00C896)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      allTaken ? Icons.check_rounded : Icons.add_rounded,
                      color: allTaken
                          ? Colors.white
                          : const Color(0xFF667085),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(allTaken ? 'Taken' : 'Log dose',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: allTaken
                                ? Colors.white
                                : const Color(0xFF344054))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}