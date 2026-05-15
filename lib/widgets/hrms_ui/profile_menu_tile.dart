import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HrmsTokens.surface,
        borderRadius: HrmsTokens.rMd(),
        child: InkWell(
          onTap: onTap,
          borderRadius: HrmsTokens.rMd(),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: HrmsTokens.rMd(),
              border: Border.all(color: HrmsTokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HrmsTokens.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: HrmsTokens.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: HrmsTokens.text)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: GoogleFonts.inter(fontSize: 12, color: HrmsTokens.muted)),
                        ],
                      ],
                    ),
                  ),
                  trailing ?? const Icon(Icons.chevron_right_rounded, color: HrmsTokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPanelCard extends StatelessWidget {
  const AdminPanelCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HrmsTokens.s4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HrmsTokens.primary.withValues(alpha: 0.12),
            HrmsTokens.primarySoft,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: HrmsTokens.rLg(),
        border: Border.all(color: HrmsTokens.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HrmsTokens.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.admin_panel_settings_outlined, color: HrmsTokens.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'Admin panel',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: HrmsTokens.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
