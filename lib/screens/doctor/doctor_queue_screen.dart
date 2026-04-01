import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/queue_model.dart';
import '../../services/firestore_service.dart';

class DoctorQueueScreen extends StatelessWidget {
  final String clinicId;
  const DoctorQueueScreen({super.key, required this.clinicId});

  @override
  Widget build(BuildContext context) {
    final db = FirestoreService();

    return StreamBuilder<List<QueueEntry>>(
      stream: db.queueStream(clinicId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }

        final entries = snapshot.data ?? [];

        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color:        const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.queue_rounded,
                      color: Color(0xFF6C63FF), size: 36),
                ),
                const SizedBox(height: 16),
                Text('Queue is empty',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('No patients waiting right now.',
                    style: GoogleFonts.dmSans(
                        color: const Color(0xFF667085))),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (ctx, i) {
            final e = entries[i];
            return _QueueCard(
              entry:    e,
              position: i + 1,
              clinicId: clinicId,
              db:       db,
            );
          },
        );
      },
    );
  }
}

// ─── Queue Card ───────────────────────────────────────────────────────────────

class _QueueCard extends StatelessWidget {
  final QueueEntry entry;
  final int        position;
  final String     clinicId;
  final FirestoreService db;

  const _QueueCard({
    required this.entry,
    required this.position,
    required this.clinicId,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(entry.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (statusInfo['border'] as Color).withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ──
          Row(
            children: [
              // Queue number
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color:        _priorityColor(entry.priority).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text('#$position',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          color: _priorityColor(entry.priority),
                          fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),

              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.patientName,
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize:   15,
                            color:      const Color(0xFF0D1B2A))),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:        statusInfo['bg'] as Color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(statusInfo['label'] as String,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusInfo['text'] as Color)),
                        ),
                        const SizedBox(width: 6),
                        Text('~${entry.estimatedWaitMinutes} min',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF667085))),
                      ],
                    ),
                  ],
                ),
              ),

              // Priority dot
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: _priorityColor(entry.priority),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Symptoms ──
          if (entry.symptoms.isNotEmpty)
            Wrap(
              spacing: 6, runSpacing: 4,
              children: entry.symptoms
                  .map((s) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(s,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF344054))),
              ))
                  .toList(),
            ),

          const SizedBox(height: 12),

          // ── Action buttons ──
          Row(
            children: [
              if (entry.status == QueueStatus.waiting)
                _ActionBtn(
                  label: 'Call',
                  icon:  Icons.notifications_active_rounded,
                  color: const Color(0xFF00C896),
                  onTap: () => db.updateQueueStatus(
                      clinicId, entry.id, QueueStatus.called),
                ),
              if (entry.status == QueueStatus.called)
                _ActionBtn(
                  label: 'In Progress',
                  icon:  Icons.medical_services_rounded,
                  color: const Color(0xFF2196F3),
                  onTap: () => db.updateQueueStatus(
                      clinicId, entry.id, QueueStatus.inProgress),
                ),
              if (entry.status == QueueStatus.inProgress)
                _ActionBtn(
                  label: 'Done',
                  icon:  Icons.check_circle_rounded,
                  color: const Color(0xFF00C896),
                  onTap: () => db.updateQueueStatus(
                      clinicId, entry.id, QueueStatus.done),
                ),
              const SizedBox(width: 8),
              _ActionBtn(
                label: 'Remove',
                icon:  Icons.remove_circle_outline_rounded,
                color: Colors.red.shade400,
                onTap: () => _confirmRemove(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from Queue'),
        content: Text(
            'Remove ${entry.patientName} from the queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              db.removeQueueEntry(clinicId, entry.id);
              Navigator.pop(context);
            },
            child: Text('Remove',
                style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }

  Color _priorityColor(int p) {
    if (p >= 9) return Colors.red;
    if (p >= 7) return Colors.orange;
    return const Color(0xFF00C896);
  }

  Map<String, dynamic> _statusInfo(QueueStatus s) {
    switch (s) {
      case QueueStatus.called:
        return {
          'label':  'Called',
          'bg':     const Color(0xFFE8F5E9),
          'text':   const Color(0xFF1B5E20),
          'border': Colors.green,
        };
      case QueueStatus.inProgress:
        return {
          'label':  'In Progress',
          'bg':     const Color(0xFFE3F2FD),
          'text':   const Color(0xFF0D47A1),
          'border': Colors.blue,
        };
      case QueueStatus.done:
        return {
          'label':  'Done',
          'bg':     const Color(0xFFF2F4F7),
          'text':   const Color(0xFF667085),
          'border': Colors.grey,
        };
      default:
        return {
          'label':  'Waiting',
          'bg':     const Color(0xFFFFF8E1),
          'text':   const Color(0xFF7A5900),
          'border': Colors.orange,
        };
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}