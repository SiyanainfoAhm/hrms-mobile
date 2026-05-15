import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(HrmsTokens.s4),
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null || leading != null || trailing != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: HrmsTokens.text),
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(fontSize: 13, height: 1.35, color: HrmsTokens.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        if (title != null || leading != null || trailing != null) const SizedBox(height: HrmsTokens.s3),
        child,
      ],
    );

    return Material(
      color: HrmsTokens.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: HrmsTokens.rLg(),
      child: InkWell(
        onTap: onTap,
        borderRadius: HrmsTokens.rLg(),
        splashColor: HrmsTokens.primary.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: HrmsTokens.rLg(),
            border: Border.all(color: HrmsTokens.border),
            boxShadow: [HrmsTokens.shadowSm()],
          ),
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
  }
}
