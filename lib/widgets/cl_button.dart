import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── CareLoop Button ─────────────────────────────────────────────────────────

class ClButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final Color? color;
  final IconData? icon;

  const ClButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF00C896),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB2DFD5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: GoogleFonts.dmSans(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

// ─── CareLoop Text Field ──────────────────────────────────────────────────────

class ClTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;

  const ClTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF344054))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 20, color: const Color(0xFF667085))
                : null,
            suffixIcon: suffixIcon != null
                ? GestureDetector(
                    onTap: onSuffixTap,
                    child: Icon(suffixIcon, size: 20, color: const Color(0xFF667085)),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

// ─── Stat Card ───────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? sublabel;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF0D1B2A))),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF667085))),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(sublabel!,
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ─── Risk Badge ──────────────────────────────────────────────────────────────

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
        border: Border.all(color: (info['border'] as Color)),
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
