import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/doctor_chat_provider.dart';
import '../../providers/auth_provider.dart';

class DoctorChatScreen extends StatefulWidget {
  const DoctorChatScreen({super.key});

  @override
  State<DoctorChatScreen> createState() => _DoctorChatScreenState();
}

class _DoctorChatScreenState extends State<DoctorChatScreen> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker     = ImagePicker();

  // ── Send text ─────────────────────────────────────────────────────────────
  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    context.read<DoctorChatProvider>().sendMessage(text);
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

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
    final doctor = context.read<AuthProvider>().doctor;
    await context.read<DoctorChatProvider>().resetSession(doctor);
    Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
  }

  // ── Image pick ────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera) return;
    try {
      final XFile? file = await _picker.pickImage(
        source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes    = await file.readAsBytes();
      final mimeType = file.mimeType ?? 'image/jpeg';
      final text     = _ctrl.text.trim();
      _ctrl.clear();
      if (!mounted) return;
      context.read<DoctorChatProvider>().sendMessageWithImage(
        text.isEmpty ? 'Please analyze this medical image/report.' : text,
        bytes, mimeType,
      );
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Attach Medical Image',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Send an X-ray, report, or medical image for AI clinical analysis.',
                style: GoogleFonts.dmSans(
                    color: const Color(0xFF667085), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!kIsWeb) ...[
                    Expanded(
                      child: _ImageOptionBtn(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        color: const Color(0xFF6C63FF),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: _ImageOptionBtn(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: const Color(0xFF00C896),
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
    // ✅ Uses DoctorChatProvider — fully separate from patient ChatProvider
    final chat = context.watch<DoctorChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Doctor AI',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Clinical assistant',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: const Color(0xFF667085))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:     const Icon(Icons.refresh_rounded),
            tooltip:  'New session',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Quick prompts ──────────────────────────────────────────────────
          if (chat.messages.isNotEmpty && !chat.thinking)
            _QuickPrompts(onTap: (s) { _ctrl.text = s; _send(); }),

          // ── Messages ───────────────────────────────────────────────────────
          Expanded(
            child: !chat.sessionReady
                ? const _LoadingState()
                : chat.messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
              controller: _scrollCtrl,
              padding:    const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount:  chat.messages.length + (chat.thinking ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == chat.messages.length) return const _TypingIndicator();
                return _MessageBubble(msg: chat.messages[i])
                    .animate().fadeIn(duration: 250.ms).slideY(begin: 0.15);
              },
            ),
          ),

          // ── Input bar ──────────────────────────────────────────────────────
          _InputBar(
            ctrl:       _ctrl,
            onSend:     _send,
            thinking:   chat.thinking,
            onImageTap: _showImageOptions,
          ),
        ],
      ),
    );
  }
}

// ─── Quick Prompts ────────────────────────────────────────────────────────────

class _QuickPrompts extends StatelessWidget {
  final Function(String) onTap;
  static const _prompts = [
    'How are my patients today?',
    'Check patient status',
    'Send appointment request',
    'Review recent alerts',
    'Patient medication summary',
  ];
  const _QuickPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color:  const Color(0xFFF8FFFE),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: 12),
        children: _prompts.map((p) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label:           Text(p, style: const TextStyle(fontSize: 12)),
            onPressed:       () => onTap(p),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE4E7EC)),
            padding:         EdgeInsets.zero,
            labelPadding:    const EdgeInsets.symmetric(horizontal: 10),
          ),
        )).toList(),
      ),
    );
  }
}

// ─── Message Bubble — uses DoctorChatMessage ──────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final DoctorChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    // isDoctor=true means the DOCTOR typed it (right side, purple)
    // isDoctor=false means the AI replied (left side, white)
    final isDoc = msg.isDoctor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        isDoc ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isDoc)
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color:        const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 16),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
              isDoc ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDoc
                        ? const Color(0xFF6C63FF)
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isDoc ? 18 : 4),
                      bottomRight: Radius.circular(isDoc ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color:     Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset:    const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (msg.hasImage && isDoc) ...[
                        const Icon(Icons.image_rounded,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          msg.text,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            color: isDoc
                                ? Colors.white
                                : const Color(0xFF0D1B2A),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Show action badge if AI performed an action
                if (!isDoc && msg.action != null) ...[
                  const SizedBox(height: 6),
                  _ActionBadge(action: msg.action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final String action;
  const _ActionBadge({required this.action});

  String get _label {
    switch (action) {
      case 'check_patient_status':     return '🔍 Patient status checked';
      case 'send_appointment_request': return '📅 Appointment request sent';
      case 'send_patient_message':     return '💬 Message sent to patient';
      case 'acknowledge_alert':        return '✅ Alert acknowledged';
      default:                         return action;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color:        const Color(0xFFEDE9FF),
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
    ),
    child: Text(_label,
        style: const TextStyle(
            fontSize: 11, color: Color(0xFF4B44CC),
            fontWeight: FontWeight.w600)),
  );
}

// ─── Typing Indicator ─────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color:        const Color(0xFF6C63FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 16),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18), topRight: Radius.circular(18),
                bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06), blurRadius: 8)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                width: 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                    color: Color(0xFF6C63FF), shape: BoxShape.circle),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .fadeOut(
                  delay:    Duration(milliseconds: i * 200),
                  duration: 400.ms)
                  .then()
                  .fadeIn(duration: 400.ms)),
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
  final VoidCallback           onSend;
  final VoidCallback           onImageTap;
  final bool                   thinking;
  const _InputBar({
    required this.ctrl, required this.onSend,
    required this.thinking, required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        children: [
          // Image attach button
          GestureDetector(
            onTap: thinking ? null : onImageTap,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: thinking
                    ? const Color(0xFFF2F4F7)
                    : const Color(0xFF6C63FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: thinking
                      ? const Color(0xFFE4E7EC)
                      : const Color(0xFF6C63FF).withOpacity(0.3),
                ),
              ),
              child: Icon(Icons.add_photo_alternate_rounded,
                  color: thinking
                      ? const Color(0xFFB0BAC9)
                      : const Color(0xFF6C63FF),
                  size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller:         ctrl,
              onSubmitted:        (_) => onSend(),
              enabled:            !thinking,
              maxLines:           null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: thinking
                    ? 'AI is thinking…'
                    : 'Ask about a patient or send a message…',
                hintStyle: GoogleFonts.dmSans(
                    color: const Color(0xFFB0BAC9), fontSize: 14),
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
                color: thinking
                    ? const Color(0xFF6C63FF).withOpacity(0.3)
                    : const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Option Button ──────────────────────────────────────────────────────

class _ImageOptionBtn extends StatelessWidget {
  final IconData  icon;
  final String    label;
  final Color     color;
  final VoidCallback onTap;
  const _ImageOptionBtn({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
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
          decoration: BoxDecoration(
            color:        const Color(0xFF6C63FF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.smart_toy_rounded,
              color: Color(0xFF6C63FF), size: 36),
        ),
        const SizedBox(height: 16),
        Text('Doctor AI',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Starting clinical session…',
            style: GoogleFonts.dmSans(
                color: const Color(0xFF667085), fontSize: 14)),
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: Color(0xFF6C63FF)),
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
        const Icon(Icons.chat_bubble_outline_rounded,
            color: Color(0xFF6C63FF), size: 48),
        const SizedBox(height: 16),
        Text('Ask me anything',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Query patients, send messages, review alerts',
            style: GoogleFonts.dmSans(
                color: const Color(0xFF667085), fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_rounded,
                color: Color(0xFF6C63FF), size: 16),
            const SizedBox(width: 4),
            Text('Attach medical images for AI analysis',
                style: GoogleFonts.dmSans(
                    color: const Color(0xFF6C63FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    ),
  );
}