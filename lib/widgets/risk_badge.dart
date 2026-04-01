import 'package:flutter/material.dart';

class RiskBadge extends StatelessWidget {
  final String risk;
  const RiskBadge({super.key, required this.risk});

  @override
  Widget build(BuildContext context) {
    final info = _info(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: info['bg'] as Color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info['border'] as Color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info['icon'] as IconData, size: 14, color: info['color'] as Color),
          const SizedBox(width: 4),
          Text(info['label'] as String,
              style: TextStyle(
                  fontSize: 12,
                  color: info['color'] as Color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Map<String, dynamic> _info(String risk) {
    switch (risk.toLowerCase()) {
      case 'high':
        return {
          'label': 'High Risk — Action Taken',
          'icon': Icons.warning_rounded,
          'color': Colors.red.shade700,
          'bg': Colors.red.shade50,
          'border': Colors.red.shade200,
        };
      case 'medium':
        return {
          'label': 'Monitoring Closely',
          'icon': Icons.info_outline_rounded,
          'color': Colors.orange.shade700,
          'bg': Colors.orange.shade50,
          'border': Colors.orange.shade200,
        };
      default:
        return {
          'label': 'Recovering Well',
          'icon': Icons.check_circle_outline_rounded,
          'color': Colors.green.shade700,
          'bg': Colors.green.shade50,
          'border': Colors.green.shade200,
        };
    }
  }
}
