import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/patient_model.dart';
import '../../models/medication_model.dart';
import '../../services/firestore_service.dart';
import 'doctor_add_medication_screen.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  final _db           = FirestoreService();
  final _searchCtrl   = TextEditingController();
  String _query       = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller:  _searchCtrl,
            onChanged:   (v) => setState(() => _query = v.toLowerCase()),
            decoration: InputDecoration(
              hintText:   'Search patient by name or email…',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Color(0xFF667085)),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                icon:     const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              )
                  : null,
            ),
          ),
        ),

        // ── Patient list ──
        Expanded(
          child: StreamBuilder<List<PatientModel>>(
            stream: _db.allPatientsStream(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF6C63FF)));
              }

              final all      = snap.data ?? [];
              final filtered = _query.isEmpty
                  ? all
                  : all
                  .where((p) =>
              p.name.toLowerCase().contains(_query) ||
                  p.email.toLowerCase().contains(_query))
                  .toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No patients registered yet.'
                        : 'No patients match "$_query".',
                    style: GoogleFonts.dmSans(
                        color: const Color(0xFF667085)),
                  ),
                );
              }

              return ListView.builder(
                padding:     const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount:   filtered.length,
                itemBuilder: (ctx, i) =>
                    _PatientCard(patient: filtered[i], db: _db),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Patient Card ─────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final PatientModel     patient;
  final FirestoreService db;
  const _PatientCard({required this.patient, required this.db});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF00C896).withOpacity(0.15),
          child: Text(
            patient.name.isNotEmpty
                ? patient.name[0].toUpperCase()
                : '?',
            style: const TextStyle(
                color:      Color(0xFF00C896),
                fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(patient.name,
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(patient.email,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: const Color(0xFF667085))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add medication button
            IconButton(
              icon:    const Icon(Icons.add_circle_rounded,
                  color: Color(0xFF00C896)),
              tooltip: 'Add Medication',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DoctorAddMedicationScreen(patient: patient),
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded,
                color: Color(0xFF667085)),
          ],
        ),
        children: [
          // Medications list
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: StreamBuilder<List<Medication>>(
              stream: db.medicationsStream(patient.id),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(
                        color: Color(0xFF00C896)),
                  );
                }
                final meds = snap.data ?? [];
                if (meds.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No medications assigned.',
                        style: GoogleFonts.dmSans(
                            color: const Color(0xFF667085),
                            fontSize: 13)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Medications',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w600,
                            fontSize:   13,
                            color:      const Color(0xFF344054))),
                    const SizedBox(height: 8),
                    ...meds.map((m) => _MedRow(
                      med: m,
                      db:  db,
                      onRemove: () =>
                          db.deactivateMedication(m.id),
                    )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Medication Row inside patient card ──────────────────────────────────────

class _MedRow extends StatelessWidget {
  final Medication       med;
  final FirestoreService db;
  final VoidCallback     onRemove;
  const _MedRow(
      {required this.med, required this.db, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final taken   = med.isTakenToday;
    final takePct = taken ? 1.0 : 0.0; // simple today-only indicator

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        taken
            ? const Color(0xFF00C896).withOpacity(0.06)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: taken
              ? const Color(0xFF00C896).withOpacity(0.3)
              : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            taken
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: taken ? const Color(0xFF00C896) : Colors.orange,
            size:  20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        fontSize:   13,
                        color:      const Color(0xFF0D1B2A))),
                Text(
                  '${med.dosage} · ${med.frequency}'
                      '${med.reminderTimes.isNotEmpty ? " · ${med.reminderTimes.join(", ")}" : ""}',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: const Color(0xFF667085)),
                ),
                const SizedBox(height: 4),
                Text(
                  taken ? '✓ Taken today' : '⚠ Not taken yet today',
                  style: TextStyle(
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                    color: taken
                        ? const Color(0xFF00C896)
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          // Remove (deactivate) medication
          IconButton(
            icon:     const Icon(Icons.delete_outline_rounded,
                color: Color(0xFF667085), size: 18),
            tooltip:  'Remove medication',
            onPressed: () => _confirmRemove(context),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Remove Medication'),
        content: Text('Remove ${med.name} from this patient?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onRemove();
              Navigator.pop(context);
            },
            child: Text('Remove',
                style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }
}