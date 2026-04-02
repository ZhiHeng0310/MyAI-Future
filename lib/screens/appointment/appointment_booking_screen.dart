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

class _AppointmentBookingScreenState
    extends State<AppointmentBookingScreen> {
  final _db       = FirestoreService();
  final _schedule = DoctorSchedule(doctorId: '');

  DateTime      _selectedDate = DateTime.now().add(const Duration(days: 1));
  String?       _selectedSlot;
  List<String>  _bookedSlots  = [];
  bool          _loadingSlots = false;
  bool          _booking      = false;
  String?       _error;

  // Shown when slot is taken
  List<Map<String, dynamic>> _alternatives = [];
  bool _showAlternatives = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() { _loadingSlots = true; _selectedSlot = null; });
    _bookedSlots = await _db.getBookedSlots(widget.doctor.id, _selectedDate);
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
        _error          = 'That slot is already taken.';
        _alternatives   = result.alternatives;
        _showAlternatives = true;
        _booking        = false;
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color:        const Color(0xFF00C896).withOpacity(0.1),
                shape:        BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF00C896), size: 36),
            ),
            const SizedBox(height: 16),
            Text('Appointment Confirmed!',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Dr. ${appt.doctorName}\n${appt.dateLabel} at ${appt.timeSlot}',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: const Color(0xFF667085)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // go back
            },
            child: const Text('Great!',
                style: TextStyle(color: Color(0xFF00C896))),
          ),
        ],
      ),
    );
    setState(() => _booking = false);
  }

  @override
  Widget build(BuildContext context) {
    final allSlots = _schedule.allSlots;

    return Scaffold(
      appBar: AppBar(
        title: Text('Book Appointment',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Doctor info ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        const Color(0xFF6C63FF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                    const Color(0xFF6C63FF).withOpacity(0.2),
                    child: Text(widget.doctor.name[0],
                        style: const TextStyle(
                            color:      Color(0xFF6C63FF),
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dr. ${widget.doctor.name}',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w700)),
                      Text(
                        widget.doctor.specialization ??
                            'General Practitioner',
                        style: GoogleFonts.dmSans(
                            color: const Color(0xFF667085),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Date picker ──
            Text('Select Date',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount:       14,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final d     = DateTime.now().add(Duration(days: i + 1));
                  final isWkd = d.weekday == 6 || d.weekday == 7;
                  final isSel = _isSameDay(d, _selectedDate);
                  return GestureDetector(
                    onTap: isWkd ? null : () {
                      setState(() => _selectedDate = d);
                      _loadSlots();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF6C63FF)
                            : isWkd
                            ? const Color(0xFFF2F4F7)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF6C63FF)
                              : const Color(0xFFE4E7EC),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_dayName(d),
                              style: TextStyle(
                                fontSize: 11,
                                color: isSel
                                    ? Colors.white70
                                    : isWkd
                                    ? const Color(0xFFB0BAC9)
                                    : const Color(0xFF667085),
                              )),
                          const SizedBox(height: 4),
                          Text('${d.day}',
                              style: TextStyle(
                                fontSize:   18,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? Colors.white
                                    : isWkd
                                    ? const Color(0xFFB0BAC9)
                                    : const Color(0xFF0D1B2A),
                              )),
                          Text(_monthName(d),
                              style: TextStyle(
                                fontSize: 10,
                                color: isSel
                                    ? Colors.white70
                                    : const Color(0xFF667085),
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // ── Time slots ──
            Text('Select Time',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),

            if (_loadingSlots)
              const Center(child: CircularProgressIndicator(
                  color: Color(0xFF6C63FF)))
            else
              Wrap(
                spacing: 10, runSpacing: 10,
                children: allSlots.map((slot) {
                  final taken = _bookedSlots.contains(slot);
                  final isSel = _selectedSlot == slot;
                  return GestureDetector(
                    onTap: taken ? null : () =>
                        setState(() => _selectedSlot = slot),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: taken
                            ? const Color(0xFFF2F4F7)
                            : isSel
                            ? const Color(0xFF6C63FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: taken
                              ? const Color(0xFFE4E7EC)
                              : isSel
                              ? const Color(0xFF6C63FF)
                              : const Color(0xFFE4E7EC),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (taken)
                            const Icon(Icons.block_rounded,
                                size: 12, color: Color(0xFFB0BAC9)),
                          if (taken) const SizedBox(width: 4),
                          Text(
                            slot,
                            style: TextStyle(
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                              color: taken
                                  ? const Color(0xFFB0BAC9)
                                  : isSel
                                  ? Colors.white
                                  : const Color(0xFF344054),
                            ),
                          ),
                          if (taken) ...[
                            const SizedBox(width: 4),
                            Text('Taken',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFB0BAC9))),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            // ── Error / alternatives ──
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
                    style: TextStyle(
                        color: Colors.red.shade700, fontSize: 13)),
              ),
            ],

            if (_showAlternatives && _alternatives.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Available alternatives:',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600, fontSize: 13)),
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
                        Text(
                          '${_fullDateStr(date)} at $slot',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF00C896)),
                        ),
                        const Spacer(),
                        const Text('Select →',
                            style: TextStyle(
                                color:    Color(0xFF00C896),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 32),

            // ── Book button ──
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: (_selectedSlot == null || _booking)
                    ? null
                    : _book,
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
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : Text(
                    _selectedSlot == null
                        ? 'Select a time slot'
                        : 'Book $_selectedSlot on ${_fullDateStr(_selectedDate)}',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
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