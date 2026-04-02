import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/medication_provider.dart';
import '../../models/medication_model.dart';

class MedicationScreen extends StatelessWidget {
  const MedicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final meds = context.watch<MedicationProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: meds.medications.isEmpty
          ? _EmptyMeds()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AdherenceCard(
              takenSlots: meds.takenSlotsToday,
              totalSlots: meds.totalSlotsToday,
              rate:       meds.adherenceRate,
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),

            const SizedBox(height: 24),

            Text("Today's Schedule",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 17)),

            const SizedBox(height: 12),

            ...meds.medications.asMap().entries.map((e) =>
                _MedCard(
                  med:   e.value,
                  onLogSlot: (slot, taken) =>
                      context.read<MedicationProvider>()
                          .logDoseForSlot(e.value.id, slot, taken),
                  onLogSingle: (taken) =>
                      context.read<MedicationProvider>()
                          .logDose(e.value.id, taken),
                ).animate(
                    delay: Duration(milliseconds: 150 + e.key * 60))
                    .fadeIn().slideX(begin: 0.1)),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─── Adherence Card ───────────────────────────────────────────────────────────

class _AdherenceCard extends StatelessWidget {
  final int    takenSlots;
  final int    totalSlots;
  final double rate;
  const _AdherenceCard({
    required this.takenSlots,
    required this.totalSlots,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final pct   = (rate * 100).round();
    final color = rate >= 0.8
        ? const Color(0xFF00C896)
        : rate >= 0.5
        ? Colors.orange
        : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90, height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(PieChartData(
                  sections: [
                    PieChartSectionData(
                        value: rate * 100, color: color,
                        radius: 12, showTitle: false),
                    PieChartSectionData(
                        value: (1 - rate) * 100,
                        color: const Color(0xFFF2F4F7),
                        radius: 12, showTitle: false),
                  ],
                  sectionsSpace: 2, centerSpaceRadius: 30,
                )),
                Text('$pct%',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Adherence Today',
                    style: GoogleFonts.dmSans(
                        color: const Color(0xFF667085), fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '$takenSlots of $totalSlots doses taken',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: const Color(0xFF0D1B2A)),
                ),
                const SizedBox(height: 4),
                Text(
                  rate == 1.0
                      ? 'All doses taken today! 🎉'
                      : rate >= 0.5
                      ? 'Keep it up — almost there!'
                      : 'Don\'t forget your medications',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: color,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value:           rate,
                    backgroundColor: const Color(0xFFF2F4F7),
                    valueColor:      AlwaysStoppedAnimation<Color>(color),
                    minHeight:       8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Med Card ─────────────────────────────────────────────────────────────────

class _MedCard extends StatelessWidget {
  final Medication              med;
  final Function(String, bool)  onLogSlot;    // (timeSlot, taken)
  final Function(bool)          onLogSingle;  // for meds with no reminder times

  const _MedCard({
    required this.med,
    required this.onLogSlot,
    required this.onLogSingle,
  });

  @override
  Widget build(BuildContext context) {
    final allTaken = med.isTakenToday;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allTaken
              ? const Color(0xFF00C896).withOpacity(0.35)
              : const Color(0xFFE4E7EC),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: allTaken
                      ? const Color(0xFF00C896).withOpacity(0.1)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.medication_liquid_rounded,
                    color: allTaken
                        ? const Color(0xFF00C896)
                        : const Color(0xFF667085),
                    size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(med.name,
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize:   16,
                            color:      const Color(0xFF0D1B2A))),
                    Text('${med.dosage} · ${med.frequency}',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color:    const Color(0xFF667085))),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Per-slot buttons OR single button ──────────────────────────
          if (med.reminderTimes.isEmpty)
          // No reminder times — single toggle
            _SingleDoseBtn(
              taken:   med.isTakenToday,
              onTap:   () => onLogSingle(!med.isTakenToday),
            )
          else
          // One button per reminder time ─────────────────────────────────
            Wrap(
              spacing: 10, runSpacing: 10,
              children: med.reminderTimes.map((time) {
                final taken = med.isTakenForSlot(time);
                return _SlotBtn(
                  time:  time,
                  taken: taken,
                  onTap: () => onLogSlot(time, !taken),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── Per-slot button ───────────────────────────────────────────────────────────

class _SlotBtn extends StatelessWidget {
  final String time;
  final bool   taken;
  final VoidCallback onTap;
  const _SlotBtn({required this.time, required this.taken, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: taken
              ? const Color(0xFF00C896)
              : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: taken
                ? const Color(0xFF00C896)
                : const Color(0xFFD0D5DD),
          ),
          boxShadow: taken
              ? [BoxShadow(
              color:     const Color(0xFF00C896).withOpacity(0.3),
              blurRadius: 6)]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              taken ? Icons.check_circle_rounded : Icons.access_time_rounded,
              color: taken ? Colors.white : const Color(0xFF667085),
              size:  16,
            ),
            const SizedBox(width: 6),
            Text(
              time,
              style: TextStyle(
                color:      taken ? Colors.white : const Color(0xFF344054),
                fontWeight: FontWeight.w600,
                fontSize:   13,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              taken ? '✓' : '',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single dose button (for meds with no reminder time) ──────────────────────

class _SingleDoseBtn extends StatelessWidget {
  final bool         taken;
  final VoidCallback onTap;
  const _SingleDoseBtn({required this.taken, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding:  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: taken
              ? const Color(0xFF00C896)
              : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(12),
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
              taken ? Icons.check_rounded : Icons.add_rounded,
              color: taken ? Colors.white : const Color(0xFF667085),
              size:  18,
            ),
            const SizedBox(width: 8),
            Text(
              taken ? 'Taken today' : 'Mark as taken',
              style: TextStyle(
                color:      taken ? Colors.white : const Color(0xFF344054),
                fontWeight: FontWeight.w600,
                fontSize:   14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyMeds extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color:        const Color(0xFF00C896).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.medication_rounded,
              color: Color(0xFF00C896), size: 36),
        ),
        const SizedBox(height: 16),
        Text('No medications yet',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          'Your doctor will add medications\nafter your consultation.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
              color: const Color(0xFF667085), fontSize: 14),
        ),
      ],
    ),
  );
}
