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
    final rate = meds.adherenceRate;

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: meds.medications.isEmpty
          ? _EmptyMeds()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Adherence Chart
                  _AdherenceCard(rate: rate)
                      .animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),

                  const SizedBox(height: 24),

                  Text("Today's Schedule",
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 17))
                      .animate(delay: 100.ms).fadeIn(),

                  const SizedBox(height: 12),

                  ...meds.medications.asMap().entries.map((e) =>
                      _MedCard(
                        med: e.value,
                        onLog: (taken) =>
                            context.read<MedicationProvider>().logDose(e.value.id, taken),
                      ).animate(delay: Duration(milliseconds: 150 + e.key * 60))
                          .fadeIn()
                          .slideX(begin: 0.1)),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

// ─── Adherence Card ───────────────────────────────────────────────────────────

class _AdherenceCard extends StatelessWidget {
  final double rate;
  const _AdherenceCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100).round();
    final color = rate >= 0.8
        ? const Color(0xFF00C896)
        : rate >= 0.5
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          // Donut
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: rate * 100,
                        color: color,
                        radius: 12,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: (1 - rate) * 100,
                        color: const Color(0xFFF2F4F7),
                        radius: 12,
                        showTitle: false,
                      ),
                    ],
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                  ),
                ),
                Text('$pct%',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w700, color: color)),
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
                  rate == 1.0
                      ? 'All medications taken! 🎉'
                      : rate >= 0.5
                          ? 'Keep it up — almost there'
                          : 'Don\'t forget your medications',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: const Color(0xFF0D1B2A)),
                ),
                const SizedBox(height: 8),
                _RateBar(rate: rate, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  final double rate;
  final Color color;
  const _RateBar({required this.rate, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: rate,
        backgroundColor: const Color(0xFFF2F4F7),
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 8,
      ),
    );
  }
}

// ─── Med Card ────────────────────────────────────────────────────────────────

class _MedCard extends StatelessWidget {
  final Medication med;
  final Function(bool) onLog;
  const _MedCard({required this.med, required this.onLog});

  @override
  Widget build(BuildContext context) {
    final taken = med.isTakenToday;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: taken
              ? const Color(0xFF00C896).withOpacity(0.35)
              : const Color(0xFFE4E7EC),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: taken
                  ? const Color(0xFF00C896).withOpacity(0.1)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.medication_liquid_rounded,
              color: taken ? const Color(0xFF00C896) : const Color(0xFF667085),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: const Color(0xFF0D1B2A))),
                const SizedBox(height: 2),
                Text('${med.dosage} · ${med.frequency}',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: const Color(0xFF667085))),
                if (med.reminderTimes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: med.reminderTimes
                        .map((t) => Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(t,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF344054))),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          // Toggle
          Column(
            children: [
              GestureDetector(
                onTap: () => onLog(!taken),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: taken
                        ? const Color(0xFF00C896)
                        : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    taken ? Icons.check_rounded : Icons.add_rounded,
                    color: taken ? Colors.white : const Color(0xFF667085),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(taken ? 'Taken' : 'Log',
                  style: TextStyle(
                      fontSize: 11,
                      color: taken
                          ? const Color(0xFF00C896)
                          : const Color(0xFF667085))),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyMeds extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
            child: const Icon(Icons.medication_rounded,
                color: Color(0xFF00C896), size: 36),
          ),
          const SizedBox(height: 16),
          Text('No medications yet',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Your doctor will add medications after your consultation.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: const Color(0xFF667085), fontSize: 14)),
        ],
      ),
    );
  }
}
