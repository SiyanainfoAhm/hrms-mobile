import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconBackground,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconBackground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : HrmsTokens.s3),
      decoration: BoxDecoration(
        color: HrmsTokens.surface,
        borderRadius: HrmsTokens.rMd(),
        border: Border.all(color: HrmsTokens.border),
        boxShadow: [HrmsTokens.shadowSm()],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: compact ? 36 : 42,
              height: compact ? 36 : 42,
              decoration: BoxDecoration(
                color: iconBackground ?? HrmsTokens.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: HrmsTokens.primary, size: compact ? 20 : 22),
            ),
            SizedBox(width: compact ? 10 : 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: HrmsTokens.muted, letterSpacing: 0.2),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w800,
                    color: HrmsTokens.text,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
