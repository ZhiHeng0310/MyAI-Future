// lib/widgets/inbox_icon.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/inbox_service.dart';

class InboxIcon extends StatelessWidget {
  const InboxIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<InboxService>(
      builder: (context, inbox, _) {
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () {
                Navigator.pushNamed(context, '/inbox');
              },
            ),

            // Red dot indicator for unread notifications
            if (inbox.hasUnread)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      inbox.unreadCount > 99 ? '99+' : '${inbox.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Animated version with pulse effect
class InboxIconAnimated extends StatefulWidget {
  const InboxIconAnimated({Key? key}) : super(key: key);

  @override
  State<InboxIconAnimated> createState() => _InboxIconAnimatedState();
}

class _InboxIconAnimatedState extends State<InboxIconAnimated>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InboxService>(
      builder: (context, inbox, _) {
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () {
                Navigator.pushNamed(context, '/inbox');
              },
            ),

            // Animated red dot for unread notifications
            if (inbox.hasUnread)
              Positioned(
                right: 8,
                top: 8,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Center(
                      child: Text(
                        inbox.unreadCount > 99 ? '99+' : '${inbox.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}