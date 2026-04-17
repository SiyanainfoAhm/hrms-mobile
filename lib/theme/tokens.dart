import 'package:flutter/material.dart';

/// Design tokens aligned to `hrms-web` (`src/config/themeConfig.ts` + `globals.css`).
class HrmsTokens {
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);

  static const primary = Color(0xFF7C3AED);
  static const primarySoft = Color(0xFFEDE9FE);

  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);

  // Radii (web: sm 10, md 14, lg 18)
  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 18.0;

  // Spacing rhythm (mobile-friendly approximation of web Tailwind usage)
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;

  static BorderRadius rSm() => BorderRadius.circular(radiusSm);
  static BorderRadius rMd() => BorderRadius.circular(radiusMd);
  static BorderRadius rLg() => BorderRadius.circular(radiusLg);

  static BoxShadow shadowSm() => BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: 0.06),
        blurRadius: 2,
        offset: const Offset(0, 1),
      );

  static BoxShadow shadowMd() => BoxShadow(
        color: const Color(0xFF111827).withValues(alpha: 0.12),
        blurRadius: 24,
        offset: const Offset(0, 8),
      );
}

