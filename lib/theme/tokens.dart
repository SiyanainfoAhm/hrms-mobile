import 'package:flutter/material.dart';

/// HRMS mobile design tokens (SaaS / Material 3).
class HrmsTokens {
  static const bg = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  static const primary = Color(0xFF7C3AED);
  static const primaryDark = Color(0xFF5B21B6);
  static const primarySoft = Color(0xFFEDE9FE);

  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);

  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 24.0;

  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;

  static BorderRadius rSm() => BorderRadius.circular(radiusSm);
  static BorderRadius rMd() => BorderRadius.circular(radiusMd);
  static BorderRadius rLg() => BorderRadius.circular(radiusLg);
  static BorderRadius rXl() => BorderRadius.circular(radiusXl);

  static BoxShadow shadowSm() => BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      );

  static BoxShadow shadowMd() => BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 8),
      );
}
