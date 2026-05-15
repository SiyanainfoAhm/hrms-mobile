import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

class HrmsTheme {
  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: HrmsTokens.primary,
      onPrimary: Colors.white,
      secondary: HrmsTokens.primaryDark,
      onSecondary: Colors.white,
      error: HrmsTokens.danger,
      onError: Colors.white,
      surface: HrmsTokens.surface,
      onSurface: HrmsTokens.text,
      outline: HrmsTokens.border,
      surfaceContainerHighest: const Color(0xFFF1F5F9),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HrmsTokens.bg,
      dividerColor: HrmsTokens.border,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: HrmsTokens.text,
      displayColor: HrmsTokens.text,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 22, color: HrmsTokens.text),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20, color: HrmsTokens.text),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16, color: HrmsTokens.text),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: HrmsTokens.text),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.35),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4, color: HrmsTokens.text),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.35, color: HrmsTokens.muted),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: HrmsTokens.bg,
        foregroundColor: HrmsTokens.text,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: HrmsTokens.text,
        ),
      ),
      cardTheme: CardThemeData(
        color: HrmsTokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrmsTokens.radiusLg),
          side: const BorderSide(color: HrmsTokens.border, width: 1),
        ),
        shadowColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: HrmsTokens.surface,
        indicatorColor: HrmsTokens.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final sel = s.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? HrmsTokens.primary : HrmsTokens.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final sel = s.contains(WidgetState.selected);
          return IconThemeData(color: sel ? HrmsTokens.primary : HrmsTokens.muted, size: 24);
        }),
        height: 68,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: HrmsTokens.rMd()),
        backgroundColor: HrmsTokens.text,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HrmsTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: HrmsTokens.rXl()),
        titleTextStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18, color: HrmsTokens.text),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HrmsTokens.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: Color(0xFFCBD5E1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrmsTokens.radiusXl)),
        ),
        showDragHandle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HrmsTokens.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: HrmsTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: HrmsTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: HrmsTokens.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: HrmsTokens.danger),
        ),
        hintStyle: GoogleFonts.inter(color: HrmsTokens.muted, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: HrmsTokens.muted, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HrmsTokens.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HrmsTokens.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HrmsTokens.text,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          side: const BorderSide(color: HrmsTokens.border),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HrmsTokens.primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: HrmsTokens.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: HrmsTokens.primarySoft,
        side: const BorderSide(color: HrmsTokens.border),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: HrmsTokens.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
