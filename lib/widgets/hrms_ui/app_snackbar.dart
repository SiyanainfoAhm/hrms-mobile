import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/tokens.dart';

/// Consistent floating snackbars (success / error).
void showAppSnackBar(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
      backgroundColor: error ? HrmsTokens.danger : HrmsTokens.success,
      margin: const EdgeInsets.all(HrmsTokens.s4),
    ),
  );
}

Future<bool?> showAppConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
  String cancel = 'Cancel',
  bool danger = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(left: HrmsTokens.s4, right: HrmsTokens.s4, bottom: MediaQuery.paddingOf(ctx).bottom + HrmsTokens.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: HrmsTokens.text)),
            const SizedBox(height: 8),
            Text(message, style: GoogleFonts.inter(fontSize: 14, height: 1.4, color: HrmsTokens.muted)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: danger
                        ? FilledButton.styleFrom(backgroundColor: HrmsTokens.danger, foregroundColor: Colors.white)
                        : null,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(confirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
