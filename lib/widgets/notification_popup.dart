// lib/widgets/notification_popup.dart
import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationPopup {
  static OverlayEntry? _currentOverlay;

  /// Show a popup notification that auto-dismisses after duration
  static void show(
      BuildContext context,
      NotificationModel notification, {
        Duration duration = const Duration(seconds: 4),
      }) {
    // Remove existing popup if any
    dismiss();

    final overlay = Overlay.of(context);

    _currentOverlay = OverlayEntry(
      builder: (context) => _NotificationPopupWidget(
        notification: notification,
        onDismiss: dismiss,
        duration: duration,
      ),
    );

    overlay.insert(_currentOverlay!);
  }

  /// Dismiss the current popup
  static void dismiss() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

class _NotificationPopupWidget extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback onDismiss;
  final Duration duration;

  const _NotificationPopupWidget({
    required this.notification,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_NotificationPopupWidget> createState() => _NotificationPopupWidgetState();
}

class _NotificationPopupWidgetState extends State<_NotificationPopupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);

    // Animate in
    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBackgroundColor() {
    switch (widget.notification.type) {
      case NotificationType.appointment:
        return Colors.blue.shade600;
      case NotificationType.medication:
        return Colors.orange.shade600;
      case NotificationType.queue:
        return Colors.purple.shade600;
      case NotificationType.doctor:
        return Colors.green.shade600;
      case NotificationType.general:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getBackgroundColor(),
                    _getBackgroundColor().withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () {
                  _controller.reverse().then((_) => widget.onDismiss());
                  // Navigate to inbox
                  Navigator.pushNamed(context, '/inbox');
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            widget.notification.icon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.notification.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.notification.message,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        iconSize: 20,
                        onPressed: () {
                          _controller.reverse().then((_) => widget.onDismiss());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}