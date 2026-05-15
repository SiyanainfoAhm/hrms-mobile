import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// Multicolor Google "G" for sign-in buttons.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  static const _asset = 'assets/branding/google_g.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _asset,
      width: size,
      height: size,
      semanticsLabel: 'Google',
    );
  }
}

/// Outlined sign-in button with visible Google logo (matches web auth styling).
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: HrmsTokens.text,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        side: const BorderSide(color: HrmsTokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const GoogleLogo(size: 20),
          const SizedBox(width: 12),
          Text(
            loading ? 'Please wait…' : label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
