import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/appointment_model.dart' hide HealthAlert;
import '../../models/health_alert_model.dart' hide DoctorInboxMessage;
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/inbox_service.dart';

class DoctorAlertsScreen extends StatelessWidget {
  const DoctorAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    if (doctor == null) return const SizedBox.shrink();
    final db = FirestoreService();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Dashboard',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Health Alerts'),
              Tab(text: 'Inbox'),
            ],
            labelColor: Color(0xFF6C63FF),
            unselectedLabelColor: Color(0xFF667085),
            indicatorColor: Color(0xFF6C63FF),
          ),
        ),
        body: TabBarView(
          children: [
            _AlertsList(
              doctorId: doctor.id,
              doctorName: doctor.name,
              db: db,
            ),
            _InboxList(doctorId: doctor.id, db: db),
          ],
        ),
      ),
    );
  }
}

// ─── Health Alerts List ───────────────────────────────────────────────────────

class _AlertsList extends StatelessWidget {
  final String doctorId;
  final String doctorName;
  final FirestoreService db;

  const _AlertsList({
    required this.doctorId,
    required this.doctorName,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HealthAlert>>(
      stream: db.doctorAlertsStream(doctorId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        final alerts = snap.data ?? [];
        if (alerts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: Color(0xFF00C896), size: 48),
                const SizedBox(height: 12),
                Text('No health alerts',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('All patients are doing well.',
                    style: GoogleFonts.dmSans(
                        color: const Color(0xFF667085))),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: alerts.length,
          itemBuilder: (_, i) => _AlertCard(
            alert: alerts[i],
            doctorName: doctorName,
            doctorId: doctorId,
            db: db,
          ),
        );
      },
    );
  }
}

// ─── Alert Card ───────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final HealthAlert alert;
  final String doctorName;
  final String doctorId;
  final FirestoreService db;

  const _AlertCard({
    required this.alert,
    required this.doctorName,
    required this.doctorId,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = alert.status == 'pending';
    final riskColor = alert.riskLevel == 'high'
        ? Colors.red
        : alert.riskLevel == 'medium'
        ? Colors.orange
        : const Color(0xFF00C896);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: riskColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                backgroundColor: riskColor.withOpacity(0.15),
                radius: 20,
                child: Text(
                  alert.patientName.isNotEmpty
                      ? alert.patientName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: riskColor, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.patientName,
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: riskColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${alert.riskLevel.toUpperCase()} RISK',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: riskColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(alert.createdAt),
                          style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: const Color(0xFF667085)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isPending)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00C896), size: 20),
            ],
          ),

          const SizedBox(height: 10),

          // Patient message
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FFFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '"${alert.message}"',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: const Color(0xFF344054),
                  fontStyle: FontStyle.italic),
            ),
          ),

          // Doctor's previous response
          if (alert.doctorResponse != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded,
                      color: Color(0xFF6C63FF), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your response: ${alert.doctorResponse}',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF344054)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons (only for pending alerts)
          if (isPending) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ResponseBtn(
                  label: '😴 Recommend rest',
                  color: const Color(0xFF00C896),
                  onTap: () => _respond(
                    context,
                    alert,
                    'Please rest and stay hydrated. Monitor your symptoms — '
                        'if they worsen, come in immediately.',
                  ),
                ),
                _ResponseBtn(
                  label: '📅 Request appointment',
                  color: const Color(0xFF6C63FF),
                  onTap: () => _respond(
                    context,
                    alert,
                    'Please book an appointment at your earliest convenience '
                        'so I can assess you properly.',
                  ),
                ),
                _ResponseBtn(
                  label: '🚨 Go to A&E now',
                  color: Colors.red,
                  onTap: () => _respond(
                    context,
                    alert,
                    'Based on your symptoms, please go to the emergency room '
                        'or call 999 / 911 immediately. Do not wait.',
                  ),
                ),
                _ResponseBtn(
                  label: '✅ Acknowledge',
                  color: Colors.grey,
                  onTap: () => _respond(
                    context,
                    alert,
                    'I have noted your condition. Please continue monitoring '
                        'and contact me if your symptoms change.',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Respond to alert AND send notification to PATIENT
  Future<void> _respond(
      BuildContext ctx, HealthAlert a, String doctorResponse) async {
    // 1. Update alert in Firestore
    await db.respondToAlert(a.id, doctorResponse, 'responded');

    // 2. Send to PATIENT inbox
    await InboxService.sendDoctorMessage(
      userId: a.patientId,
      doctorName: doctorName,
      doctorId: doctorId,
      message: doctorResponse,
    );

    // 3. Push notification to PATIENT
    await NotificationService.sendPushToUser(
      userId: a.patientId,
      userCollection: 'patients',
      title: '👨‍⚕️ Dr. $doctorName sent you advice',
      body: doctorResponse,
      channel: 'careloop_queue',
    );

    // 4. Local notification for doctor confirmation
    await NotificationService.showQueueStatusNotification(
      title: '✅ Response sent to ${a.patientName}',
      body: doctorResponse,
    );

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Response sent to ${a.patientName} ✅'),
          backgroundColor: const Color(0xFF00C896),
        ),
      );
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ResponseBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ResponseBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color)),
    ),
  );
}

// ─── Inbox List ───────────────────────────────────────────────────────────────

class _InboxList extends StatelessWidget {
  final String doctorId;
  final FirestoreService db;

  const _InboxList({required this.doctorId, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DoctorInboxMessage>>(
      stream: db.doctorInboxStream(doctorId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        final msgs = snap.data ?? [];
        if (msgs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inbox_outlined,
                    color: Color(0xFF667085), size: 48),
                const SizedBox(height: 12),
                Text('Inbox is empty',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final msg = msgs[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: msg.read
                    ? Colors.white
                    : const Color(0xFF6C63FF).withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: msg.read
                      ? const Color(0xFFE4E7EC)
                      : const Color(0xFF6C63FF).withOpacity(0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor:
                    const Color(0xFF6C63FF).withOpacity(0.15),
                    radius: 18,
                    child: Text(
                      msg.patientName.isNotEmpty
                          ? msg.patientName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(msg.patientName,
                                style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            if (!msg.read) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: Color(0xFF6C63FF),
                                    shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(msg.message,
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: const Color(0xFF344054))),
                        const SizedBox(height: 4),
                        Text(_timeAgo(msg.createdAt),
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: const Color(0xFF667085))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}