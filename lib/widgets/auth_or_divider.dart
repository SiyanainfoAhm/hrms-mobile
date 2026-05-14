import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HrmsTokens.muted, fontWeight: FontWeight.w600),
            ),
          ),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}
