import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/queue_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/queue_model.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _symptomsCtrl = TextEditingController();
  final List<String> _selectedSymptoms = [];

  static const _commonSymptoms = [
    'Fever', 'Headache', 'Cough', 'Sore throat',
    'Body ache', 'Fatigue', 'Nausea', 'Dizziness',
    'Chest pain', 'Shortness of breath',
  ];

  @override
  void dispose() {
    _symptomsCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinQueue() async {
    if (_selectedSymptoms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one symptom.')),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final queue = context.read<QueueProvider>();
    await queue.joinQueue(
      patientId: auth.patient?.id ?? 'guest',
      patientName: auth.patient?.name ?? 'Guest',
      symptoms: _selectedSymptoms,
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueProvider>();
    final inQueue = queue.myEntry != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Queue')),
      body: inQueue ? _InQueueView(queue: queue) : _JoinQueueView(
        selectedSymptoms: _selectedSymptoms,
        onToggleSymptom: (s) => setState(() {
          _selectedSymptoms.contains(s)
              ? _selectedSymptoms.remove(s)
              : _selectedSymptoms.add(s);
        }),
        onJoin: _joinQueue,
        loading: queue.loading,
      ),
    );
  }
}

// ─── Join Queue View ─────────────────────────────────────────────────────────

class _JoinQueueView extends StatelessWidget {
  final List<String> selectedSymptoms;
  final Function(String) onToggleSymptom;
  final VoidCallback onJoin;
  final bool loading;

  static const _commonSymptoms = [
    'Fever', 'Headache', 'Cough', 'Sore throat',
    'Body ache', 'Fatigue', 'Nausea', 'Dizziness',
    'Chest pain', 'Shortness of breath',
  ];

  const _JoinQueueView({
    required this.selectedSymptoms,
    required this.onToggleSymptom,
    required this.onJoin,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF4B44CC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.queue_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Join Queue Remotely',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Skip the waiting room. Join from anywhere.',
                          style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),

          const SizedBox(height: 28),

          Text('What brings you in today?',
              style: Theme.of(context).textTheme.titleLarge)
              .animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 4),
          Text('Select all that apply',
              style: Theme.of(context).textTheme.bodyMedium)
              .animate(delay: 130.ms).fadeIn(),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonSymptoms.asMap().entries.map((e) {
              final selected = selectedSymptoms.contains(e.value);
              return GestureDetector(
                onTap: () => onToggleSymptom(e.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF6C63FF) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF6C63FF)
                          : const Color(0xFFE4E7EC),
                    ),
                    boxShadow: selected
                        ? [BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.3),
                            blurRadius: 8)]
                        : [],
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF344054),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ).animate(delay: Duration(milliseconds: 150 + e.key * 30)).fadeIn().scale(begin: const Offset(0.9, 0.9));
            }).toList(),
          ),

          const SizedBox(height: 32),

          if (selectedSymptoms.isNotEmpty) ...[
            _UrgencyNote(symptoms: selectedSymptoms),
            const SizedBox(height: 20),
          ],

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: loading ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Join Queue',
                      style: GoogleFonts.dmSans(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),
        ],
      ),
    );
  }
}

class _UrgencyNote extends StatelessWidget {
  final List<String> symptoms;
  const _UrgencyNote({required this.symptoms});

  @override
  Widget build(BuildContext context) {
    final isUrgent = symptoms.any((s) =>
        s == 'Chest pain' || s == 'Shortness of breath');
    if (!isUrgent) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You have reported urgent symptoms. You will be prioritised in the queue.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── In Queue View ────────────────────────────────────────────────────────────

class _InQueueView extends StatelessWidget {
  final QueueProvider queue;
  const _InQueueView({required this.queue});

  @override
  Widget build(BuildContext context) {
    final entry = queue.myEntry!;
    final pos = queue.myPosition;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Position card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D1B2A), Color(0xFF1A3347)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Text('Your Queue Number',
                    style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                Text('#$pos',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 64, fontWeight: FontWeight.w700))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .shimmer(duration: 2.seconds, color: const Color(0xFF00C896)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '~${entry.estimatedWaitMinutes} min estimated wait',
                    style: GoogleFonts.dmSans(
                        color: const Color(0xFF00C896), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

          const SizedBox(height: 20),

          // Status card
          _StatusCard(status: entry.status),

          const SizedBox(height: 16),

          // Symptoms
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reported Symptoms',
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: entry.symptoms
                      .map((s) => Chip(
                            label: Text(s, style: const TextStyle(fontSize: 12)),
                            backgroundColor: const Color(0xFFF2F4F7),
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
              ],
            ),
          ).animate(delay: 200.ms).fadeIn(),

          const SizedBox(height: 16),

          // Queue list preview
          Text('Queue Status',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16))
              .animate(delay: 250.ms).fadeIn(),
          const SizedBox(height: 10),
          ...queue.entries.take(5).toList().asMap().entries.map((e) {
            final isMe = queue.myEntry?.id == e.value.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFF00C896).withOpacity(0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMe
                      ? const Color(0xFF00C896).withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Text('#${e.key + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isMe ? const Color(0xFF00C896) : const Color(0xFF667085))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMe ? 'You' : e.value.patientName.split(' ').first,
                      style: TextStyle(
                          fontWeight: isMe ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                  _PriorityDot(priority: e.value.priority),
                ],
              ),
            ).animate(delay: Duration(milliseconds: 300 + e.key * 50)).fadeIn().slideX(begin: 0.1);
          }),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final QueueStatus status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final info = _infoFor(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: info['color'] as Color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(info['icon'] as IconData, color: info['textColor'] as Color),
          const SizedBox(width: 12),
          Text(info['label'] as String,
              style: TextStyle(
                  color: info['textColor'] as Color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15)),
        ],
      ),
    );
  }

  Map<String, dynamic> _infoFor(QueueStatus s) {
    switch (s) {
      case QueueStatus.waiting:
        return {
          'label': 'Waiting in queue...',
          'icon': Icons.hourglass_top_rounded,
          'color': const Color(0xFFFFF8E1),
          'textColor': const Color(0xFF7A5900),
        };
      case QueueStatus.called:
        return {
          'label': 'Your turn! Please proceed.',
          'icon': Icons.notifications_active_rounded,
          'color': const Color(0xFFE8F5E9),
          'textColor': const Color(0xFF1B5E20),
        };
      case QueueStatus.inProgress:
        return {
          'label': 'In consultation',
          'icon': Icons.medical_services_rounded,
          'color': const Color(0xFFE3F2FD),
          'textColor': const Color(0xFF0D47A1),
        };
      default:
        return {
          'label': 'Consultation complete',
          'icon': Icons.check_circle_rounded,
          'color': const Color(0xFFE8F5E9),
          'textColor': const Color(0xFF1B5E20),
        };
    }
  }
}

class _PriorityDot extends StatelessWidget {
  final int priority;
  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = priority >= 9
        ? Colors.red
        : priority >= 7
            ? Colors.orange
            : const Color(0xFF00C896);
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
