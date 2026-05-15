import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showBack = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 6);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: showBack,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack ?? () => Navigator.maybeOf(context)?.maybePop(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: HrmsTokens.text)),
          if (subtitle != null)
            Text(subtitle!, style: GoogleFonts.inter(fontSize: 12, color: HrmsTokens.muted, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: actions,
    );
  }
}
