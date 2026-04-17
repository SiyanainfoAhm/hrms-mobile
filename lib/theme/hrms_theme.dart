import 'package:flutter/material.dart';

import 'tokens.dart';

class HrmsTheme {
  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: HrmsTokens.primary,
      onPrimary: Colors.white,
      secondary: HrmsTokens.primary,
      onSecondary: Colors.white,
      error: HrmsTokens.danger,
      onError: Colors.white,
      surface: HrmsTokens.surface,
      onSurface: HrmsTokens.text,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HrmsTokens.bg,
      dividerColor: HrmsTokens.border,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: HrmsTokens.bg,
        foregroundColor: HrmsTokens.text,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: HrmsTokens.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: HrmsTokens.text),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: HrmsTokens.text),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: HrmsTokens.text),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: HrmsTokens.muted),
      ),
      cardTheme: const CardThemeData(
        color: HrmsTokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HrmsTokens.radiusMd)),
          side: BorderSide(color: HrmsTokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HrmsTokens.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HrmsTokens.radiusSm),
          borderSide: const BorderSide(color: HrmsTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HrmsTokens.radiusSm),
          borderSide: const BorderSide(color: HrmsTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HrmsTokens.radiusSm),
          borderSide: const BorderSide(color: HrmsTokens.primary, width: 1.2),
        ),
        hintStyle: const TextStyle(color: HrmsTokens.muted),
        labelStyle: const TextStyle(color: HrmsTokens.muted, fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HrmsTokens.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrmsTokens.radiusSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HrmsTokens.text,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrmsTokens.radiusSm)),
          side: const BorderSide(color: HrmsTokens.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: HrmsTokens.primarySoft,
        side: const BorderSide(color: HrmsTokens.border),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: HrmsTokens.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

