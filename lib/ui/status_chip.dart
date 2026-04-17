import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.value});
  final String value;

  (Color bg, Color fg, IconData icon) _style() {
    final v = value.toLowerCase();
    switch (v) {
      case 'approved':
        return (const Color(0xFFDCFCE7), HrmsTokens.success, Icons.check_circle_outline);
      case 'rejected':
        return (const Color(0xFFFEE2E2), HrmsTokens.danger, Icons.cancel_outlined);
      case 'cancelled':
        return (const Color(0xFFE2E8F0), HrmsTokens.muted, Icons.remove_circle_outline);
      case 'paid':
        return (const Color(0xFFE0F2FE), const Color(0xFF075985), Icons.payments_outlined);
      case 'pending':
      default:
        return (const Color(0xFFFFF7ED), const Color(0xFF9A3412), Icons.hourglass_bottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _style();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            value.toUpperCase(),
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

