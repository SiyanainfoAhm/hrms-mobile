import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

/// Privacy Policy and Terms links (login, signup, profile).
class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({
    super.key,
    this.center = true,
    this.dense = false,
    this.showAgreementLine = false,
  });

  final bool center;
  final bool dense;

  /// When true, shows "By continuing, you agree to…" (for signup).
  final bool showAgreementLine;

  @override
  Widget build(BuildContext context) {
    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: dense ? 11 : 12,
          color: HrmsTokens.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        );
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: dense ? 11 : 12,
          color: HrmsTokens.muted,
          height: 1.4,
        );

    final privacyRecognizer = TapGestureRecognizer()..onTap = () => context.push('/privacy');
    final termsRecognizer = TapGestureRecognizer()..onTap = () => context.push('/terms');

    final align = center ? TextAlign.center : TextAlign.start;

    if (showAgreementLine) {
      return Text.rich(
        TextSpan(
          style: mutedStyle,
          children: [
            const TextSpan(text: 'By creating an account, you agree to our '),
            TextSpan(text: 'Terms and Conditions', style: linkStyle, recognizer: termsRecognizer),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy Policy', style: linkStyle, recognizer: privacyRecognizer),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: align,
      );
    }

    return Text.rich(
      TextSpan(
        style: mutedStyle,
        children: [
          TextSpan(text: 'Privacy Policy', style: linkStyle, recognizer: privacyRecognizer),
          const TextSpan(text: '  ·  '),
          TextSpan(text: 'Terms and Conditions', style: linkStyle, recognizer: termsRecognizer),
        ],
      ),
      textAlign: align,
    );
  }
}
