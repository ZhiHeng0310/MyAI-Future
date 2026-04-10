import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/patient_model.dart';
import '../../models/medication_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/cl_button.dart' as clButton;
import 'doctor_add_medication_screen.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  final _db         = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctorId = context.watch<AuthProvider>().doctor?.id;

    return Column(
      children: [
        // ── Prescribe button ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: clButton.ClButton(
            label:     'Prescribe Medication to Patient',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PatientSearchScreen(db: _db, doctorId: doctorId),
              ),
            ),
            icon:     Icons.add_rounded,
          ),
        ),

        // ── Search bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged:  (v) => setState(() => _query = v.toLowerCase()),
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
            stream: doctorId == null
                ? Stream.value(const <PatientModel>[])
                : _db.doctorPatientsStream(doctorId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF6C63FF)));
              }

              final all      = snap.data ?? [];
              final filtered = _query.isEmpty
                  ? all
                  : all.where((p) =>
              p.name.toLowerCase().contains(_query) ||
                  p.email.toLowerCase().contains(_query))
                  .toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          color: Color(0xFF667085), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? 'No patients registered yet.'
                            : 'No patients match "$_query".',
                        style: GoogleFonts.dmSans(
                            color: const Color(0xFF667085)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding:     const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount:   filtered.length,
                itemBuilder: (_, i) =>
                    _PatientCard(
                      patient: filtered[i],
                      db: _db,
                      doctorId: doctorId,
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Patient Card ─────────────────────────────────────────────────────────────

class _PatientCard extends StatefulWidget {
  final PatientModel     patient;
  final FirestoreService db;
  final String?          doctorId;
  const _PatientCard({
    required this.patient,
    required this.db,
    required this.doctorId,
  });

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        children: [
          // ── Header row (always visible) ────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                    const Color(0xFF00C896).withOpacity(0.15),
                    child: Text(
                      widget.patient.name.isNotEmpty
                          ? widget.patient.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color:      Color(0xFF00C896),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.patient.name,
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        Text(widget.patient.email,
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: const Color(0xFF667085))),
                        if (widget.patient.diagnosis != null)
                          Text('Dx: ${widget.patient.diagnosis}',
                              style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  color: const Color(0xFF00C896),
                                  fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  // ✅ FIX 2: Add medication button always visible
                  IconButton(
                    icon:     const Icon(Icons.medication_rounded,
                        color: Color(0xFF00C896)),
                    tooltip:  'Add Medication',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DoctorAddMedicationScreen(
                            patient: widget.patient),
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF667085),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded: Medications ──────────────────────────────────────
          if (_expanded)
            Container(
              decoration: BoxDecoration(
                color:        const Color(0xFFF8FFFE),
                borderRadius: const BorderRadius.only(
                  bottomLeft:  Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                // ✅ FIX 2: StreamBuilder for live medication updates
                child: StreamBuilder<List<Medication>>(
                  stream: widget.doctorId == null
                      ? Stream.value(const <Medication>[])
                      : widget.db.medicationsStreamForDoctor(
                          widget.patient.id,
                          widget.doctorId!,
                        ),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: LinearProgressIndicator(
                            color: Color(0xFF00C896)),
                      );
                    }

                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade600, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Unable to load medications. '
                                    'Ensure Firestore rules are deployed.',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: Colors.orange.shade700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final meds = snap.data ?? [];

                    if (meds.isEmpty) {
                      return Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: Color(0xFF667085), size: 16),
                          const SizedBox(width: 8),
                          Text('No medications assigned yet.',
                              style: GoogleFonts.dmSans(
                                  color: const Color(0xFF667085),
                                  fontSize: 13)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DoctorAddMedicationScreen(
                                    patient: widget.patient),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded,
                                size: 14, color: Color(0xFF00C896)),
                            label: Text('Add',
                                style: GoogleFonts.dmSans(
                                    color: const Color(0xFF00C896),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Medications',
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize:   13,
                                    color:      const Color(0xFF344054))),
                            const Spacer(),
                            Text('${meds.length} assigned',
                                style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: const Color(0xFF667085))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...meds.map((m) => _MedRow(
                          med:      m,
                          onRemove: () =>
                              widget.db.deactivateMedication(m.id),
                        )),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Medication Row ───────────────────────────────────────────────────────────

class _MedRow extends StatelessWidget {
  final Medication   med;
  final VoidCallback onRemove;
  const _MedRow({required this.med, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final taken = med.isTakenToday;

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
          // Status icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: taken
                  ? const Color(0xFF00C896).withOpacity(0.12)
                  : Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              taken
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: taken ? const Color(0xFF00C896) : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          // Medication info
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
                const SizedBox(height: 2),
                // Slot-level adherence: e.g. "2 of 3 doses taken today"
                Text(
                  taken
                      ? '✓ All doses taken today'
                      : med.reminderTimes.isEmpty
                      ? '⚠ Not taken yet today'
                      : '${med.takenSlotsToday}/${med.totalSlotsToday} doses taken today',
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
          // Remove button
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title:   Text('Remove Medication',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Remove ${med.name} from this patient?',
            style: GoogleFonts.dmSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              onRemove();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ─── Patient Search Screen ───────────────────────────────────────────────────

class _PatientSearchScreen extends StatefulWidget {
  final FirestoreService db;
  final String? doctorId;
  const _PatientSearchScreen({required this.db, required this.doctorId});

  @override
  State<_PatientSearchScreen> createState() => _PatientSearchScreenState();
}

class _PatientSearchScreenState extends State<_PatientSearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Patients'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search patient by name or email…',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF667085)),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
                    : null,
              ),
            ),
          ),

          // Patient list
          Expanded(
            child: StreamBuilder<List<PatientModel>>(
              stream: widget.db.allPatientsStream(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF6C63FF)));
                }

                final all = snap.data ?? [];
                final filtered = _query.isEmpty
                    ? all
                    : all.where((p) =>
                p.name.toLowerCase().contains(_query) ||
                    p.email.toLowerCase().contains(_query))
                    .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline_rounded,
                            color: Color(0xFF667085), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No patients registered.'
                              : 'No patients match "$_query".',
                          style: GoogleFonts.dmSans(
                              color: const Color(0xFF667085)),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF00C896).withOpacity(0.15),
                      child: Text(
                        filtered[i].name.isNotEmpty
                            ? filtered[i].name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Color(0xFF00C896),
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(filtered[i].name,
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                    subtitle: Text(filtered[i].email,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: const Color(0xFF667085))),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xFF667085)),
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => DoctorAddMedicationScreen(
                            patient: filtered[i]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
