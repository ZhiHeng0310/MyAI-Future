import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/risk_badge.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    context.read<ChatProvider>().sendMessage(text);
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
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

  /// ── FIXED reload: calls resetSession which recreates GeminiService ────────
  Future<void> _reload() async {
    final patient = context.read<AuthProvider>().patient;
    await context.read<ChatProvider>().resetSession(patient);
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
    final chat = context.watch<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        const Color(0xFF00C896),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 18),
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
            // ✅ Fixed: was clearChat() which left session stuck
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Quick reply chips ─────────────────────────────────────────────
          if (chat.messages.isNotEmpty && !chat.thinking)
            _QuickReplies(onTap: (s) {
              _ctrl.text = s;
              _send();
            }),

          // ── Messages ──────────────────────────────────────────────────────
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
                if (i == chat.messages.length) {
                  return const _TypingIndicator();
                }
                return _MessageBubble(msg: chat.messages[i])
                    .animate()
                    .fadeIn(duration: 250.ms)
                    .slideY(begin: 0.15);
              },
            ),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          _InputBar(
              ctrl: _ctrl, onSend: _send, thinking: chat.thinking),
        ],
      ),
    );
  }
}

// ─── Quick Reply Chips ────────────────────────────────────────────────────────

class _QuickReplies extends StatelessWidget {
  final Function(String) onTap;
  static const _chips = [
    'How am I doing?',
    'Book appointment',
    'Medication reminder',
    'I feel worse',
    'I feel better',
  ];
  const _QuickReplies({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color:  const Color(0xFFF8FFFE),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: 12),
        children: _chips.map((c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label:           Text(c, style: const TextStyle(fontSize: 12)),
            onPressed:       () => onTap(c),
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

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color:        const Color(0xFF00C896),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 16),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF0D1B2A)
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color:     Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset:    const Offset(0, 2))
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      color:    isUser
                          ? Colors.white
                          : const Color(0xFF0D1B2A),
                      height: 1.5,
                    ),
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
                    children: msg.actions
                        .map((a) => _ActionChip(label: _labelFor(a)))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(String a) {
    switch (a) {
      case 'alert_doctor':      return '🚨 Doctor alerted';
      case 'suggest_revisit':   return '📅 Revisit suggested';
      case 'increase_priority': return '⬆️ Priority raised';
      case 'remind_medication': return '💊 Reminder sent';
      default:                  return a;
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  const _ActionChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color:        const Color(0xFFFFF3CD),
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: const Color(0xFFFFE083)),
    ),
    child: Text(label,
        style: const TextStyle(
            fontSize: 11, color: Color(0xFF7A5900))),
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
              color:        const Color(0xFF00C896),
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
                    color: Color(0xFF00C896), shape: BoxShape.circle),
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
  final bool                   thinking;
  const _InputBar({required this.ctrl, required this.onSend, required this.thinking});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              controller:             ctrl,
              onSubmitted:            (_) => onSend(),
              enabled:                !thinking,
              maxLines:               null,
              textCapitalization:     TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: thinking
                    ? 'CareLoop AI is thinking…'
                    : 'Type a message…',
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
                    ? const Color(0xFFE8F7F3)
                    : const Color(0xFF00C896),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.send_rounded,
                  color: thinking
                      ? const Color(0xFF00C896)
                      : Colors.white,
                  size: 20),
            ),
          ),
        ],
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
            color:        const Color(0xFF00C896).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.smart_toy_rounded,
              color: Color(0xFF00C896), size: 36),
        ),
        const SizedBox(height: 16),
        Text('CareLoop AI',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Starting your session…',
            style: GoogleFonts.dmSans(
                color: const Color(0xFF667085), fontSize: 14)),
        const SizedBox(height: 24),
        const SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF00C896)),
        ),
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
            color: Color(0xFF00C896), size: 48),
        const SizedBox(height: 16),
        Text('Start a conversation',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Ask me anything about your health',
            style: GoogleFonts.dmSans(
                color: const Color(0xFF667085), fontSize: 14)),
      ],
    ),
  );
}
