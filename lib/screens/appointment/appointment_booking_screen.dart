import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/appointment_model.dart';
import '../../models/doctor_model.dart';
import '../../models/patient_model.dart';
import '../../providers/appointment_provider.dart';
import '../../services/firestore_service.dart';

class AppointmentBookingScreen extends StatefulWidget {
  final DoctorModel  doctor;
  final PatientModel patient;
  final List<String> initialSymptoms;

  const AppointmentBookingScreen({
    super.key,
    required this.doctor,
    required this.patient,
    this.initialSymptoms = const [],
  });

  @override
  State<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState extends State<AppointmentBookingScreen> {
  final _db       = FirestoreService();
  final _schedule = DoctorSchedule(doctorId: '');

  DateTime     _selectedDate = DateTime.now().add(const Duration(days: 1));
  String?      _selectedSlot;
  List<String> _bookedSlots  = [];
  bool         _loadingSlots = false;
  bool         _booking      = false;
  String?      _error;

  List<Map<String, dynamic>> _alternatives   = [];
  bool                       _showAlternatives = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() { _loadingSlots = true; _selectedSlot = null; });
    try {
      _bookedSlots = await _db.getBookedSlots(widget.doctor.id, _selectedDate);
    } catch (_) {
      _bookedSlots = [];
    }
    setState(() => _loadingSlots = false);
  }

  Future<void> _book() async {
    if (_selectedSlot == null) return;
    setState(() { _booking = true; _error = null; _showAlternatives = false; });

    final result = await context.read<AppointmentProvider>().bookAppointment(
      doctor:   widget.doctor,
      patient:  widget.patient,
      date:     _selectedDate,
      timeSlot: _selectedSlot!,
      symptoms: widget.initialSymptoms,
    );

    if (!mounted) return;

    if (result.success) {
      _showSuccessAndPop(result.appointment!);
    } else if (result.isSlotTaken) {
      setState(() {
        _error            = 'That slot is already taken.';
        _alternatives     = result.alternatives;
        _showAlternatives = true;
        _booking          = false;
      });
    } else {
      setState(() { _error = result.errorMessage; _booking = false; });
    }
  }

  void _selectAlternative(Map<String, dynamic> alt) {
    setState(() {
      _selectedDate     = alt['date'] as DateTime;
      _selectedSlot     = alt['timeSlot'] as String;
      _showAlternatives = false;
      _error            = null;
    });
    _loadSlots();
  }

  void _showSuccessAndPop(AppointmentSlot appt) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color:  const Color(0xFF00C896).withOpacity(0.1),
                shape:  BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF00C896), size: 40),
            ),
            const SizedBox(height: 16),
            Text('Appointment Confirmed!',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 18),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        const Color(0xFF00C896).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF00C896).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  _ConfirmRow(
                    icon:  Icons.person_rounded,
                    label: 'Doctor',
                    value: 'Dr. ${appt.doctorName}',
                  ),
                  const SizedBox(height: 8),
                  _ConfirmRow(
                    icon:  Icons.calendar_today_rounded,
                    label: 'Date',
                    value: appt.dateLabel,
                  ),
                  const SizedBox(height: 8),
                  _ConfirmRow(
                    icon:  Icons.access_time_rounded,
                    label: 'Time',
                    value: appt.timeSlot,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // go back to chat/home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Great! Done'),
            ),
          ),
        ],
      ),
    );
    setState(() => _booking = false);
  }

  @override
  Widget build(BuildContext context) {
    final allSlots    = _schedule.allSlots;
    final availSlots  = allSlots.where((s) => !_bookedSlots.contains(s)).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFE),
      appBar: AppBar(
        title: Text('Book Appointment',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Doctor info card ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color:        const Color(0xFF6C63FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        widget.doctor.name.isNotEmpty
                            ? widget.doctor.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color:      Color(0xFF6C63FF),
                            fontWeight: FontWeight.w700,
                            fontSize:   20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dr. ${widget.doctor.name}',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(
                          widget.doctor.specialization ?? 'General Practitioner',
                          style: GoogleFonts.dmSans(
                              color:    const Color(0xFF667085),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:        const Color(0xFF00C896).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('9:00 AM – 5:00 PM',
                              style: GoogleFonts.dmSans(
                                  fontSize:   11,
                                  color:      const Color(0xFF00C896),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Symptoms shown (from AI chat) ───────────────────────────────
            if (widget.initialSymptoms.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reason for visit:',
                              style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w600,
                                  fontSize:   12,
                                  color:      Colors.orange.shade800)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6, runSpacing: 4,
                            children: widget.initialSymptoms.map((s) =>
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:        Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(s,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade800)),
                                )).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Step 1: Pick a date ─────────────────────────────────────────
            _StepHeader(step: '1', title: 'Select a Date'),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection:  Axis.horizontal,
                itemCount:        14,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d      = DateTime.now().add(Duration(days: i + 1));
                  final isWkd  = d.weekday == 6 || d.weekday == 7;
                  final isSel  = _isSameDay(d, _selectedDate);
                  final isToday = _isSameDay(d, DateTime.now().add(
                      const Duration(days: 1)));

                  return GestureDetector(
                    onTap: isWkd ? null : () {
                      setState(() => _selectedDate = d);
                      _loadSlots();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 60,
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF6C63FF)
                            : isWkd
                            ? const Color(0xFFF2F4F7)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF6C63FF)
                              : isToday && !isSel
                              ? const Color(0xFF00C896)
                              : const Color(0xFFE4E7EC),
                          width: isToday && !isSel ? 2 : 1,
                        ),
                        boxShadow: isSel ? [
                          BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.3),
                              blurRadius: 8)
                        ] : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_dayName(d),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isSel
                                      ? Colors.white70
                                      : isWkd
                                      ? const Color(0xFFB0BAC9)
                                      : const Color(0xFF667085))),
                          const SizedBox(height: 4),
                          Text('${d.day}',
                              style: TextStyle(
                                  fontSize:   18,
                                  fontWeight: FontWeight.w700,
                                  color: isSel
                                      ? Colors.white
                                      : isWkd
                                      ? const Color(0xFFB0BAC9)
                                      : const Color(0xFF0D1B2A))),
                          Text(_monthName(d),
                              style: TextStyle(
                                  fontSize: 9,
                                  color: isSel
                                      ? Colors.white70
                                      : const Color(0xFF667085))),
                          if (isWkd)
                            Text('Closed',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.red.shade300)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // ── Step 2: Pick a time slot ────────────────────────────────────
            Row(
              children: [
                _StepHeader(step: '2', title: 'Select a Time Slot'),
                const Spacer(),
                if (!_loadingSlots)
                  Text(
                    '$availSlots slots available',
                    style: GoogleFonts.dmSans(
                        fontSize:   12,
                        color:      availSlots > 0
                            ? const Color(0xFF00C896)
                            : Colors.red.shade400,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loadingSlots)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                      color: Color(0xFF6C63FF)),
                ),
              )
            else if (allSlots.isEmpty)
              _EmptySlots(date: _selectedDate)
            else
              _TimeSlotGrid(
                allSlots:     allSlots,
                bookedSlots:  _bookedSlots,
                selectedSlot: _selectedSlot,
                onSelect:     (slot) => setState(() => _selectedSlot = slot),
              ),

            // ── Error / Alternatives ────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],

            if (_showAlternatives && _alternatives.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('🔄 Available alternatives:',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ..._alternatives.map((alt) {
                final date = alt['date'] as DateTime;
                final slot = alt['timeSlot'] as String;
                return GestureDetector(
                  onTap: () => _selectAlternative(alt),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        const Color(0xFF00C896).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF00C896).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_rounded,
                            color: Color(0xFF00C896), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_fullDateStr(date)} at $slot',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF00C896),
                                fontSize: 13),
                          ),
                        ),
                        const Text('Tap to select →',
                            style: TextStyle(
                                color:    Color(0xFF00C896),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 28),

            // ── Summary before booking ──────────────────────────────────────
            if (_selectedSlot != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4B44CC)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selected appointment',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white70, fontSize: 11)),
                          Text(
                            '${_fullDateStr(_selectedDate)} at $_selectedSlot',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _selectedSlot = null),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 18),
                      tooltip: 'Clear selection',
                    ),
                  ],
                ),
              ),

            // ── Book button ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: (_selectedSlot == null || _booking) ? null : _book,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                  const Color(0xFF6C63FF).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _booking
                    ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _selectedSlot == null
                          ? 'Select a date and time above'
                          : 'Confirm Booking',
                      style: GoogleFonts.dmSans(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayName(DateTime d) {
    const n = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return n[d.weekday - 1];
  }

  String _monthName(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return m[d.month - 1];
  }

  String _fullDateStr(DateTime d) =>
      '${_dayName(d)} ${d.day} ${_monthName(d)}';
}

// ─── Time Slot Grid ────────────────────────────────────────────────────────────

class _TimeSlotGrid extends StatelessWidget {
  final List<String> allSlots;
  final List<String> bookedSlots;
  final String?      selectedSlot;
  final ValueChanged<String> onSelect;

  const _TimeSlotGrid({
    required this.allSlots,
    required this.bookedSlots,
    required this.selectedSlot,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: allSlots.map((slot) {
        final taken = bookedSlots.contains(slot);
        final isSel = selectedSlot == slot;
        return GestureDetector(
          onTap: taken ? null : () => onSelect(slot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 90, height: 56,
            decoration: BoxDecoration(
              color: taken
                  ? const Color(0xFFF2F4F7)
                  : isSel
                  ? const Color(0xFF6C63FF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: taken
                    ? const Color(0xFFE4E7EC)
                    : isSel
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFFD0D5DD),
                width: isSel ? 2 : 1,
              ),
              boxShadow: isSel ? [
                BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                    blurRadius: 8)
              ] : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  taken
                      ? Icons.block_rounded
                      : isSel
                      ? Icons.check_circle_rounded
                      : Icons.access_time_rounded,
                  size:  16,
                  color: taken
                      ? const Color(0xFFB0BAC9)
                      : isSel
                      ? Colors.white
                      : const Color(0xFF667085),
                ),
                const SizedBox(height: 4),
                Text(
                  slot,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color: taken
                        ? const Color(0xFFB0BAC9)
                        : isSel
                        ? Colors.white
                        : const Color(0xFF344054),
                  ),
                ),
                if (taken)
                  Text('Booked',
                      style: TextStyle(
                          fontSize: 9, color: Colors.red.shade300)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Step Header ──────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final String step;
  final String title;
  const _StepHeader({required this.step, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color:  const Color(0xFF6C63FF),
            shape:  BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700, fontSize: 15,
                color: const Color(0xFF0D1B2A))),
      ],
    );
  }
}

// ─── Empty Slots ──────────────────────────────────────────────────────────────

class _EmptySlots extends StatelessWidget {
  final DateTime date;
  const _EmptySlots({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_rounded, color: Colors.orange.shade600, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No available slots for this date. '
                  'Please select another day.',
              style: GoogleFonts.dmSans(
                  color: Colors.orange.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Confirm Row ──────────────────────────────────────────────────────────────

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _ConfirmRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00C896)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: GoogleFonts.dmSans(
                fontSize: 13, color: const Color(0xFF667085))),
        Expanded(
          child: Text(value,
              style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: const Color(0xFF0D1B2A))),
        ),
      ],
    );
  }
}