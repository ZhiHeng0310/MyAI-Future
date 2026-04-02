import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    context.read<DoctorChatProvider>().sendMessage(text);
    Future.delayed(
        const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve:    Curves.easeOut,
      );
    }
  }

  Future<void> _reload() async {
    final doctor = context.read<AuthProvider>().doctor;
    await context.read<DoctorChatProvider>().resetSession(doctor);
    Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  borderRadius: BorderRadius.circular(10)),
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
                        fontSize: 11,
                        color: const Color(0xFF667085))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reload),
        ],
      ),
      body: Column(
        children: [
          // Quick prompts
          if (chat.messages.isNotEmpty && !chat.thinking)
            _QuickPrompts(onTap: (s) { _ctrl.text = s; _send(); }),

          Expanded(
            child: !chat.sessionReady
                ? _LoadingState()
                : chat.messages.isEmpty
                ? _EmptyState()
                : ListView.builder(
              controller: _scrollCtrl,
              padding:    const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount:  chat.messages.length +
                  (chat.thinking ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == chat.messages.length) {
                  return const _Thinking();
                }
                final msg = chat.messages[i];
                return _Bubble(msg: msg);
              },
            ),
          ),

          _InputBar(ctrl: _ctrl, onSend: _send, thinking: chat.thinking),
        ],
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final Function(String) onTap;
  static const _prompts = [
    'How are my patients today?',
    'Ask Ahmad to book appointment',
    'Send message to patient',
    'Check patient status',
  ];
  const _QuickPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    color:  const Color(0xFFF8FFFE),
    child:  ListView(
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
          labelPadding:
          const EdgeInsets.symmetric(horizontal: 10),
        ),
      )).toList(),
    ),
  );
}

class _Bubble extends StatelessWidget {
  final DoctorChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
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
            child: Container(
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
                      blurRadius: 8, offset: const Offset(0, 2))
                ],
              ),
              child: Text(msg.text,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color:    isDoc ? Colors.white : const Color(0xFF0D1B2A),
                    height:   1.5,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 30, height: 30,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
              color:        const Color(0xFF6C63FF),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.smart_toy_rounded,
              color: Colors.white, size: 16),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8)],
          ),
          child: const SizedBox(
            width: 40, height: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Dot(delay: 0),
                _Dot(delay: 200),
                _Dot(delay: 400),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  Widget build(BuildContext context) => Container(
    width: 7, height: 7,
    decoration: const BoxDecoration(
        color: Color(0xFF6C63FF), shape: BoxShape.circle),
  );
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  final bool thinking;
  const _InputBar(
      {required this.ctrl, required this.onSend, required this.thinking});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
            color:     Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset:    const Offset(0, -4))
      ],
    ),
    child: Row(
      children: [
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
        const SizedBox(width: 10),
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

class _LoadingState extends StatelessWidget {
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
        Text('Starting session…',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: Color(0xFF6C63FF)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
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
        Text('Query patients, send messages, manage appointments',
            style: GoogleFonts.dmSans(
                color: const Color(0xFF667085), fontSize: 14)),
      ],
    ),
  );
}