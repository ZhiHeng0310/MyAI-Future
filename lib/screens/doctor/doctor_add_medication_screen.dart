import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/patient_model.dart';
import '../../models/medication_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/cl_button.dart' as clButton;
import '../../widgets/cl_text_field.dart';

class DoctorAddMedicationScreen extends StatefulWidget {
  final PatientModel patient;
  const DoctorAddMedicationScreen({super.key, required this.patient});

  @override
  State<DoctorAddMedicationScreen> createState() =>
      _DoctorAddMedicationScreenState();
}

class _DoctorAddMedicationScreenState
    extends State<DoctorAddMedicationScreen> {
  final _db         = FirestoreService();
  final _nameCtrl   = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  String _frequency = 'Once daily';
  final List<TextEditingController> _timeCtrl = [
    TextEditingController(text: '08:00')
  ];

  bool _saving  = false;
  String? _error;

  static const _frequencies = [
    'Once daily',
    'Twice daily',
    'Three times daily',
    'Four times daily',
    'As needed',
  ];

  // Auto-populate reminder times when frequency changes
  void _onFrequencyChanged(String? val) {
    if (val == null) return;
    setState(() {
      _frequency = val;
      _timeCtrl.clear();
      switch (val) {
        case 'Twice daily':
          _timeCtrl.addAll([
            TextEditingController(text: '08:00'),
            TextEditingController(text: '20:00'),
          ]);
          break;
        case 'Three times daily':
          _timeCtrl.addAll([
            TextEditingController(text: '08:00'),
            TextEditingController(text: '14:00'),
            TextEditingController(text: '20:00'),
          ]);
          break;
        case 'Four times daily':
          _timeCtrl.addAll([
            TextEditingController(text: '07:00'),
            TextEditingController(text: '12:00'),
            TextEditingController(text: '17:00'),
            TextEditingController(text: '22:00'),
          ]);
          break;
        default:
          _timeCtrl.add(TextEditingController(text: '08:00'));
      }
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _dosageCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Medicine name and dosage are required.');
      return;
    }

    setState(() {
      _saving = true;
      _error  = null;
    });

    try {
      final reminderTimes = _frequency == 'As needed'
          ? <String>[]
          : _timeCtrl.map((c) => c.text.trim()).toList();

      final med = Medication(
        id:            '',
        patientId:     widget.patient.id,
        name:          _nameCtrl.text.trim(),
        dosage:        _dosageCtrl.text.trim(),
        frequency:     _frequency,
        reminderTimes: reminderTimes,
        active:        true,
      );

      await _db.addMedication(med);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${med.name} added for ${widget.patient.name}',
            ),
            backgroundColor: const Color(0xFF00C896),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _timeCtrl) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Medication',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        const Color(0xFF00C896).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF00C896).withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                    const Color(0xFF00C896).withOpacity(0.2),
                    child: Text(
                      widget.patient.name[0].toUpperCase(),
                      style: const TextStyle(
                          color:      Color(0xFF00C896),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.patient.name,
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w700)),
                      Text(widget.patient.email,
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: const Color(0xFF667085))),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Medicine name
            clButton.ClTextField(
              controller: _nameCtrl,
              label:      'Medicine Name',
              hint:       'e.g. Paracetamol, Amoxicillin',
              prefixIcon: Icons.medication_rounded,
            ),

            const SizedBox(height: 16),

            // Dosage
            clButton.ClTextField(
              controller: _dosageCtrl,
              label:      'Dosage',
              hint:       'e.g. 500mg, 1 tablet',
              prefixIcon: Icons.scale_rounded,
            ),

            const SizedBox(height: 16),

            // Frequency dropdown
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Frequency',
                    style: GoogleFonts.dmSans(
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                        color:      const Color(0xFF344054))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value:       _frequency,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.schedule_rounded,
                        size: 20, color: Color(0xFF667085)),
                    filled:     true,
                    fillColor:  const Color(0xFFF2F4F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:   BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  items: _frequencies
                      .map((f) => DropdownMenuItem(
                      value: f, child: Text(f)))
                      .toList(),
                  onChanged: _onFrequencyChanged,
                ),
              ],
            ),

            // Reminder times (hidden for "As needed")
            if (_frequency != 'As needed') ...[
              const SizedBox(height: 16),
              Text('Reminder Times',
                  style: GoogleFonts.dmSans(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      const Color(0xFF344054))),
              const SizedBox(height: 6),
              Text(
                'Patient will receive a notification at these times daily.',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: const Color(0xFF667085)),
              ),
              const SizedBox(height: 10),
              ...List.generate(_timeCtrl.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _TimePickerField(
                        controller: _timeCtrl[i],
                        label:      'Reminder ${i + 1}',
                      ),
                    ),
                  ],
                ),
              )),
            ],

            const SizedBox(height: 16),

            // Notes
            clButton.ClTextField(
              controller: _notesCtrl,
              label:      'Notes for patient (optional)',
              hint:       'e.g. Take after meals',
              prefixIcon: Icons.notes_rounded,
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error!,
                    style:
                    TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ),
            ],

            const SizedBox(height: 32),

            clButton.ClButton(
              label:     'Save Medication',
              loading:   _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Time picker field with clock dialog ─────────────────────────────────────

class _TimePickerField extends StatefulWidget {
  final TextEditingController controller;
  final String                label;
  const _TimePickerField(
      {required this.controller, required this.label});

  @override
  State<_TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<_TimePickerField> {
  Future<void> _pick() async {
    final parts = widget.controller.text.split(':');
    final initial = TimeOfDay(
      hour:   int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        widget.controller.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pick,
      child: AbsorbPointer(
        child: clButton.ClTextField(
          controller: widget.controller,
          label:      widget.label,
          hint:       '08:00',
          prefixIcon: Icons.access_time_rounded,
        ),
      ),
    );
  }
}