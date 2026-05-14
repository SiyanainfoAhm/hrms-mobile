import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Signflow-style auth chrome: branded gradient panel + light card (split on tablet/desktop).
class HrmsAuthShell extends StatelessWidget {
  const HrmsAuthShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  static const logoAsset = 'assets/branding/hrms_agent_logo.png';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;

        if (wide) {
          return Scaffold(
            backgroundColor: HrmsTokens.bg,
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 42, child: _BrandPanel(wide: true)),
                  Expanded(
                    flex: 58,
                    child: _FormPanel(title: title, subtitle: subtitle, child: child),
                  ),
                ],
              ),
            ),
          );
        }

        final brandHeight = math.min(280.0, math.max(200.0, c.maxHeight * 0.30)).clamp(200.0, 280.0).toDouble();

        return Scaffold(
          backgroundColor: HrmsTokens.bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: brandHeight,
                  child: _BrandPanel(wide: false),
                ),
                Expanded(
                  child: _FormPanel(title: title, subtitle: subtitle, child: child),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF5B21B6),
                Color(0xFF7C3AED),
                Color(0xFF0D9488),
              ],
            ),
          ),
        ),
        Positioned(
          right: -36,
          top: -36,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
        ),
        Positioned(
          left: -28,
          bottom: -20,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: wide
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _logo(context, 96),
                    const SizedBox(height: 20),
                    Text(
                      'HRMS',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Attendance, leave, and payroll in one app.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.35,
                          ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _logo(context, 80),
                    const SizedBox(height: 12),
                    Text(
                      'HRMS',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Human resources, simplified.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _logo(BuildContext context, double size) {
    final box = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [HrmsTokens.shadowMd()],
      ),
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          HrmsAuthShell.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.business_rounded, size: size * 0.45, color: Colors.white),
        ),
      ),
    );
    if (wide) {
      return box;
    }
    return Center(child: box);
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: HrmsTokens.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HrmsTokens.radiusLg),
                  side: const BorderSide(color: HrmsTokens.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: HrmsTokens.muted,
                                height: 1.4,
                              ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      child,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Secure access for authorised users only.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: HrmsTokens.muted,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
