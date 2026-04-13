import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/gemini_service.dart' hide ChatProvider, MedStatusResult, ChatMessage;
import '../../widgets/risk_badge.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker     = ImagePicker();

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    context.read<ChatProvider>().sendMessage(t);
    _delayScroll();
  }

  void _delayScroll() =>
      Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _reload() async {
    final p = context.read<AuthProvider>().patient;
    await context.read<ChatProvider>().resetSession(p);
    _delayScroll();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera) return;
    try {
      final file = await _picker.pickImage(
          source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final mime  = file.mimeType ?? 'image/jpeg';
      final text  = _ctrl.text.trim();
      _ctrl.clear();
      if (!mounted) return;
      context.read<ChatProvider>().sendMessageWithImage(
        text.isEmpty
            ? 'Please analyse this medication bill / prescription and explain it clearly.'
            : text,
        bytes,
        mime,
      );
      _delayScroll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open image: $e')));
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scan Medical Document',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Upload a medication bill, prescription, or lab report for AI analysis.',
                  style: GoogleFonts.dmSans(
                      color: const Color(0xFF667085), fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!kIsWeb) ...[
                    Expanded(
                      child: _ImgBtn(
                        icon:  Icons.camera_alt_rounded,
                        label: 'Camera',
                        color: const Color(0xFF00C896),
                        onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: _ImgBtn(
                      icon:  Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: const Color(0xFF6C63FF),
                      onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xFF00C896),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CareLoop AI',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Health Assistant',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: const Color(0xFF667085))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:    const Icon(Icons.refresh_rounded),
            tooltip: 'New session',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick reply chips
          if (chat.messages.isNotEmpty && !chat.thinking)
            _QuickReplies(onTap: (s) { _ctrl.text = s; _send(); }),

          // Messages list
          Expanded(
            child: !chat.sessionReady
                ? const _LoadingState()
                : chat.messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
              controller: _scrollCtrl,
              padding:    const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount:  chat.messages.length + (chat.thinking ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == chat.messages.length) return const _TypingDots();
                final msg = chat.messages[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Bubble(msg: msg)
                        .animate()
                        .fadeIn(duration: 250.ms)
                        .slideY(begin: 0.12),

                    // ── Step 1: Date calendar ──────────────────────────
                    if (!msg.isUser && msg.showCalendarPicker)
                      Padding(
                        padding: const EdgeInsets.only(left: 38, bottom: 8),
                        child: _CalendarPicker(
                          symptoms: msg.appointmentSymptoms,
                          onDateSelected: (date) {
                            context.read<ChatProvider>().onDateSelected(date);
                            _delayScroll();
                          },
                        ),
                      ),

                    // ── Step 2: Time slot picker ───────────────────────
                    if (!msg.isUser && msg.showTimeSlotPicker &&
                        msg.slotDate != null && msg.slotDoctor != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 38, bottom: 8),
                        child: _TimeSlotPicker(
                          date: msg.slotDate!,
                          availableSlots: msg.availableSlots,
                          doctor: msg.slotDoctor!,
                          symptoms: msg.appointmentSymptoms,
                          onSlotSelected: (date, slot, doctor) {
                            context
                                .read<ChatProvider>()
                                .onTimeSlotSelected(date, slot, doctor);
                            _delayScroll();
                          },
                        ),
                      ),

                    // ── Document analysis ─────────────────────────────
                    if (!msg.isUser && msg.documentAnalysis != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 38, bottom: 8),
                        child: _DocAnalysisCard(analysis: msg.documentAnalysis!),
                      ),

                    // ── Medication status ─────────────────────────────
                    if (!msg.isUser && msg.medicationStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 38, bottom: 8),
                        child: _MedStatusCard(status: msg.medicationStatus!),
                      ),
                  ],
                );
              },
            ),
          ),

          // Input bar
          _InputBar(
            ctrl:       _ctrl,
            onSend:     _send,
            thinking:   chat.thinking,
            onImgTap:   _showImageOptions,
          ),
        ],
      ),
    );
  }
}

// ─── Step 1: Calendar Picker ──────────────────────────────────────────────────

class _CalendarPicker extends StatelessWidget {
  final List<String>       symptoms;
  final Function(DateTime) onDateSelected;
  const _CalendarPicker({required this.symptoms, required this.onDateSelected});

  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.25)),
        boxShadow: [BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.07),
            blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: Color(0xFF6C63FF), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pick Your Appointment Date',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: const Color(0xFF0D1B2A))),
                    Text('I\'ll show available time slots for the selected day',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: const Color(0xFF667085))),
                  ],
                ),
              ),
            ],
          ),

          if (symptoms.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Reason: ${symptoms.join(", ")}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange.shade800)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          GridView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:  7,
              mainAxisSpacing:  5,
              crossAxisSpacing: 5,
              childAspectRatio: 0.82,
            ),
            itemCount: 14,
            itemBuilder: (ctx, i) {
              final d     = today.add(Duration(days: i + 1));
              final isWkd = d.weekday == 6 || d.weekday == 7;
              return _DateCell(
                date:     d,
                isWkd:    isWkd,
                dayLabel: _dy[d.weekday - 1],
                monLabel: _mo[d.month - 1],
                onTap:    isWkd ? null : () => onDateSelected(d),
              );
            },
          ),

          const SizedBox(height: 8),
          Text('🏥 Weekends closed · Tap a weekday to see available slots',
              style: GoogleFonts.dmSans(
                  fontSize: 10, color: const Color(0xFF667085))),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }
}

class _DateCell extends StatefulWidget {
  final DateTime  date;
  final bool      isWkd;
  final String    dayLabel;
  final String    monLabel;
  final VoidCallback? onTap;
  const _DateCell({
    required this.date, required this.isWkd,
    required this.dayLabel, required this.monLabel,
    this.onTap,
  });
  @override
  State<_DateCell> createState() => _DateCellState();
}

class _DateCellState extends State<_DateCell> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.isWkd ? null : (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isWkd
              ? const Color(0xFFF2F4F7)
              : _pressed
              ? const Color(0xFF6C63FF)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isWkd
                ? const Color(0xFFE4E7EC)
                : _pressed
                ? const Color(0xFF6C63FF)
                : const Color(0xFFD0D5DD),
          ),
          boxShadow: _pressed && !widget.isWkd
              ? [BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.3),
              blurRadius: 6)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.dayLabel,
                style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w600,
                    color: widget.isWkd
                        ? const Color(0xFFB0BAC9)
                        : _pressed ? Colors.white70 : const Color(0xFF667085))),
            const SizedBox(height: 2),
            Text('${widget.date.day}',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: widget.isWkd
                        ? const Color(0xFFB0BAC9)
                        : _pressed ? Colors.white : const Color(0xFF0D1B2A))),
            Text(widget.monLabel,
                style: TextStyle(
                    fontSize: 8,
                    color: widget.isWkd
                        ? const Color(0xFFB0BAC9)
                        : _pressed ? Colors.white70 : const Color(0xFF667085))),
            if (widget.isWkd)
              Text('Off',
                  style: TextStyle(fontSize: 7, color: Colors.red.shade300)),
          ],
        ),
      ),
    );
  }
}

// ─── Step 2: Time Slot Picker ─────────────────────────────────────────────────

class _TimeSlotPicker extends StatelessWidget {
  final DateTime date;
  final List<String> availableSlots;
  final dynamic doctor; // DoctorModel
  final List<String> symptoms;
  final Function(DateTime, String, dynamic) onSlotSelected;

  const _TimeSlotPicker({
    required this.date,
    required this.availableSlots,
    required this.doctor,
    required this.symptoms,
    required this.onSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00C896).withOpacity(0.3)),
        boxShadow: [BoxShadow(
            color: const Color(0xFF00C896).withOpacity(0.07),
            blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.access_time_rounded,
                    color: Color(0xFF00C896), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose a Time Slot',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: const Color(0xFF0D1B2A))),
                    Text(
                      '${availableSlots.length} slot(s) available with Dr. ${doctor.name}',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: const Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Slot grid
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableSlots.map((slot) {
              return _SlotChip(
                slot: slot,
                onTap: () => onSlotSelected(date, slot, doctor),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
          Text('Tap a slot to confirm your booking',
              style: GoogleFonts.dmSans(
                  fontSize: 10, color: const Color(0xFF667085))),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1);
  }
}

class _SlotChip extends StatefulWidget {
  final String slot;
  final VoidCallback onTap;
  const _SlotChip({required this.slot, required this.onTap});

  @override
  State<_SlotChip> createState() => _SlotChipState();
}

class _SlotChipState extends State<_SlotChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFF00C896)
              : const Color(0xFF00C896).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed
                ? const Color(0xFF00C896)
                : const Color(0xFF00C896).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: _pressed
              ? [BoxShadow(
              color: const Color(0xFF00C896).withOpacity(0.3),
              blurRadius: 8)]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 14,
              color: _pressed ? Colors.white : const Color(0xFF00C896),
            ),
            const SizedBox(width: 6),
            Text(
              widget.slot,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _pressed ? Colors.white : const Color(0xFF00C896),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Document Analysis Card ───────────────────────────────────────────────────

class _DocAnalysisCard extends StatefulWidget {
  final DocumentAnalysis analysis;
  const _DocAnalysisCard({required this.analysis});
  @override
  State<_DocAnalysisCard> createState() => _DocAnalysisCardState();
}

class _DocAnalysisCardState extends State<_DocAnalysisCard> {
  bool _open = true;

  Color get _c {
    switch (widget.analysis.type) {
      case 'prescription':   return const Color(0xFF6C63FF);
      case 'lab_report':     return const Color(0xFF2196F3);
      case 'medical_report': return const Color(0xFF00BCD4);
      default:               return const Color(0xFF00C896);
    }
  }

  String get _label {
    switch (widget.analysis.type) {
      case 'medication_bill':  return '🧾 Medication Bill';
      case 'prescription':     return '💊 Prescription';
      case 'lab_report':       return '🔬 Lab Report';
      case 'medical_report':   return '📋 Medical Report';
      default:                 return '📄 Document';
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _c.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: _c.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: _c.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.document_scanner_rounded, color: _c, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_label,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: const Color(0xFF0D1B2A))),
                        Text('AI Analysis Complete ✓',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: const Color(0xFF667085))),
                      ],
                    ),
                  ),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: const Color(0xFF667085)),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: Color(0xFFF2F4F7)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.summary.isNotEmpty) ...[
                    _Sec('📝 Summary'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FFFE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE4E7EC)),
                      ),
                      child: Text(a.summary,
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: const Color(0xFF344054), height: 1.5)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (a.items.isNotEmpty) ...[
                    Row(
                      children: [
                        _Sec('💊 Medications / Items'),
                        const Spacer(),
                        if (a.totalCost != null)
                          _Tag('Total: ${a.totalCost}', const Color(0xFF00C896)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...a.items.map((item) => _ItemRow(item: item)),
                    const SizedBox(height: 8),
                  ],
                  if (a.keyNotes.isNotEmpty) ...[
                    _Sec('⚠️ Important Notes'),
                    const SizedBox(height: 6),
                    ...a.keyNotes.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ', style: TextStyle(color: _c, fontWeight: FontWeight.bold)),
                          Expanded(child: Text(n, style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF344054)))),
                        ],
                      ),
                    )),
                    const SizedBox(height: 8),
                  ],
                  if (a.patientAdvice.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _c.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _c.withOpacity(0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, color: _c, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.patientAdvice,
                              style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF344054), height: 1.5, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1);
  }
}

class _ItemRow extends StatelessWidget {
  final MedItem item;
  const _ItemRow({required this.item});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FFFE),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE4E7EC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(item.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF0D1B2A)))),
            if (item.price != null) _Tag(item.price!, const Color(0xFF00C896)),
          ],
        ),
        if (item.dosage.isNotEmpty || item.frequency.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text([item.dosage, item.frequency].where((s) => s.isNotEmpty).join(' · '),
              style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF667085))),
        ],
        if (item.instructions.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(item.instructions, style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF344054), fontStyle: FontStyle.italic)),
        ],
      ],
    ),
  );
}

class _Sec extends StatelessWidget {
  final String t;
  const _Sec(this.t);
  @override
  Widget build(BuildContext context) => Text(t,
      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF344054)));
}

class _Tag extends StatelessWidget {
  final String t;
  final Color  c;
  const _Tag(this.t, this.c);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(t, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
  );
}

// ─── Medication Status Card ───────────────────────────────────────────────────

class _MedStatusCard extends StatelessWidget {
  final MedStatusResult status;
  const _MedStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status.noMeds) return const SizedBox.shrink();
    final color = status.allTaken ? const Color(0xFF00C896) : Colors.orange;
    final pct   = (status.adherenceRate * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(status.allTaken ? Icons.check_circle_rounded : Icons.medication_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.allTaken ? 'All Medications Taken Today ✓' : 'Medication Status — $pct%',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF0D1B2A)),
                    ),
                    Text('${status.takenSlots}/${status.totalSlots} doses taken today',
                        style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF667085))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: status.adherenceRate,
              backgroundColor: const Color(0xFFF2F4F7),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 10),
          ...status.all.map((med) {
            final isTaken = status.taken.any((t) => t.id == med.id);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isTaken ? const Color(0xFF00C896).withOpacity(0.06) : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isTaken ? const Color(0xFF00C896).withOpacity(0.25) : Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(isTaken ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isTaken ? const Color(0xFF00C896) : Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(med.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF0D1B2A))),
                        Text('${med.dosage} · ${med.frequency}', style: GoogleFonts.dmSans(fontSize: 10, color: const Color(0xFF667085))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isTaken ? const Color(0xFF00C896).withOpacity(0.1) : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isTaken ? '✓ Taken' : 'Pending',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: isTaken ? const Color(0xFF00C896) : Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: const Color(0xFF00C896), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF0D1B2A) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (msg.hasImage && isUser) ...[
                        const Icon(Icons.image_rounded, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(msg.text,
                            style: GoogleFonts.dmSans(
                                fontSize: 15,
                                color: isUser ? Colors.white : const Color(0xFF0D1B2A),
                                height: 1.5)),
                      ),
                    ],
                  ),
                ),
                if (!isUser && msg.risk != null && msg.risk != 'low') ...[
                  const SizedBox(height: 6),
                  RiskBadge(risk: msg.risk!),
                ],
                if (!isUser && msg.actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: msg.actions.map((a) {
                      if (a == 'open_image_picker') {
                        // Tappable button to open image picker
                        return _OpenImageChip(
                          onTap: () {
                            // Find the nearest ChatScreen ancestor and call its method
                            final state = context.findAncestorStateOfType<_ChatScreenState>();
                            state?._showImageOptions();
                          },
                        );
                      }
                      return _AChip(label: _lbl(a));
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lbl(String a) {
    switch (a) {
      case 'alert_doctor':          return '🚨 Doctor alerted';
      case 'alert_all_doctors':     return '🚨 Doctors alerted';
      case 'alert_support':         return '📞 Support alerted';
      case 'suggest_revisit':       return '📅 Revisit suggested';
      case 'increase_priority':     return '⬆️ Priority raised';
      case 'remind_medication':     return '💊 Reminder sent';
      case 'appointment_confirmed': return '✅ Appointment confirmed';
      case 'book_appointment':      return '📅 Book appointment';
      case 'check_medications':     return '💊 Checking meds…';
      case 'review_my_patients':    return '👥 Reviewing patients';
      case 'send_patient_message':  return '✉️ Message sent';
      default:                      return a;
    }
  }
}

class _OpenImageChip extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenImageChip({required this.onTap});

  @override
  Widget build(BuildContext context) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF00C896).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00C896).withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.upload_file_rounded, size: 13,
                  color: Color(0xFF00C896)),
              SizedBox(width: 5),
              Text('📎 Upload Bill',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00796B),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _AChip extends StatelessWidget {
  final String label;
  const _AChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3CD),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFE083)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A5900))),
  );
}

// ─── Typing Dots ──────────────────────────────────────────────────────────────
class _TypingDots extends StatelessWidget {
  const _TypingDots();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: const Color(0xFF00C896), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18), topRight: Radius.circular(18),
                bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                width: 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(color: Color(0xFF00C896), shape: BoxShape.circle),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .fadeOut(delay: Duration(milliseconds: i * 200), duration: 400.ms)
                  .then().fadeIn(duration: 400.ms)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Input Bar ────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  final VoidCallback onImgTap;
  final bool thinking;
  const _InputBar({required this.ctrl, required this.onSend, required this.thinking, required this.onImgTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: thinking ? null : onImgTap,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: thinking ? const Color(0xFFF2F4F7) : const Color(0xFF00C896).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: thinking ? const Color(0xFFE4E7EC) : const Color(0xFF00C896).withOpacity(0.3)),
              ),
              child: Icon(Icons.add_photo_alternate_rounded,
                  color: thinking ? const Color(0xFFB0BAC9) : const Color(0xFF00C896), size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => onSend(),
              enabled: !thinking,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: thinking ? 'CareLoop AI is thinking…' : 'Ask anything · book · check meds · scan bill 📄',
                hintStyle: GoogleFonts.dmSans(color: const Color(0xFFB0BAC9), fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: thinking ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: thinking ? const Color(0xFFE8F7F3) : const Color(0xFF00C896),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.send_rounded,
                  color: thinking ? const Color(0xFF00C896) : Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Replies ────────────────────────────────────────────────────────────

  class _QuickReplies extends StatelessWidget {
  final Function(String) onTap;
  static const _chips = [
  'How am I doing?',
  'Book appointment',
  'Did I take my meds?',
  'I feel unwell',
  'Scan my bill 📄',
  ];
  const _QuickReplies({required this.onTap});
  @override
  Widget build(BuildContext context) {
  return Container(
  height: 40,
  color: const Color(0xFFF8FFFE),
  child: ListView(
  scrollDirection: Axis.horizontal,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  children: _chips.map((c) => Padding(
  padding: const EdgeInsets.only(right: 8),
  child: ActionChip(
  label: Text(c, style: const TextStyle(fontSize: 12)),
  onPressed: () => onTap(c),
  backgroundColor: Colors.white,
  side: const BorderSide(color: Color(0xFFE4E7EC)),
  padding: EdgeInsets.zero,
  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
  ),
  )).toList(),
  ),
  );
  }
  }

// ─── Image Option Button ──────────────────────────────────────────────────────

  class _ImgBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _ImgBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
  onTap: onTap,
  child: Container(
  padding: const EdgeInsets.symmetric(vertical: 16),
  decoration: BoxDecoration(
  color: color.withOpacity(0.1),
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: color.withOpacity(0.3)),
  ),
  child: Column(
  children: [
  Icon(icon, color: color, size: 28),
  const SizedBox(height: 8),
  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
  ],
  ),
  ),
  );
  }

// ─── States ───────────────────────────────────────────────────────────────────

  class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => Center(
  child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
  Container(
  width: 72, height: 72,
  decoration: BoxDecoration(color: const Color(0xFF00C896).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
  child: const Icon(Icons.smart_toy_rounded, color: Color(0xFF00C896), size: 36),
  ),
  const SizedBox(height: 16),
  Text('CareLoop AI', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
  Text('Loading your health profile…', style: GoogleFonts.dmSans(color: const Color(0xFF667085), fontSize: 14)),
  const SizedBox(height: 24),
  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896))),
  ],
  ),
  );
  }

  class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
  child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
  const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF00C896), size: 48),
  const SizedBox(height: 16),
  Text('Start a conversation', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
  const SizedBox(height: 12),
  _Hint(Icons.calendar_month_rounded, const Color(0xFF6C63FF), 'Book appointment → pick date & time slot'),
  _Hint(Icons.notifications_active_rounded, Colors.red, 'Feel unwell → alerts your doctor instantly'),
  _Hint(Icons.medication_rounded, const Color(0xFF00C896), '"Did I take my meds?" → real-time check'),
  _Hint(Icons.document_scanner_rounded, Colors.orange, 'Tap 📎 → scan bills & prescriptions'),
  ],
  ),
  );
  }

  class _Hint extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   text;
  const _Hint(this.icon, this.color, this.text);
  @override
  Widget build(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
  child: Row(
  children: [
  Container(
  padding: const EdgeInsets.all(6),
  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
  child: Icon(icon, color: color, size: 14),
  ),
  const SizedBox(width: 10),
  Expanded(child: Text(text, style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF344054)))),
  ],
  ),
  );
  }