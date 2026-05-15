import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

class QuickActionTile extends StatefulWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? background;

  @override
  State<QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<QuickActionTile> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scale = 0.97),
      onPointerUp: (_) => setState(() => _scale = 1),
      onPointerCancel: (_) => setState(() => _scale = 1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: widget.background ?? HrmsTokens.surface,
          borderRadius: HrmsTokens.rMd(),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: HrmsTokens.rMd(),
            splashColor: HrmsTokens.primary.withValues(alpha: 0.1),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: HrmsTokens.rMd(),
                border: Border.all(color: HrmsTokens.border),
                boxShadow: [HrmsTokens.shadowSm()],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: HrmsTokens.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: HrmsTokens.primary, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: HrmsTokens.text, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
