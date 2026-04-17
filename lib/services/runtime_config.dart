import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class RuntimeConfig {
  RuntimeConfig._();

  static final RuntimeConfig instance = RuntimeConfig._();

  String supabaseUrl = '';
  String supabaseAnonKey = '';
  /// Public origin of the **web** HRMS app (no trailing slash), e.g. https://hrms.example.com — used to build `/invite/{token}` URLs for the Edge Function (same as `NEXT_PUBLIC_APP_URL` on web).
  String webAppInviteBaseUrl = '';

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/config.json').catchError((_) async {
      return rootBundle.loadString('assets/config.template.json');
    });
    final json = jsonDecode(raw) as Map<String, dynamic>;
    supabaseUrl = (json['supabaseUrl'] ?? '').toString().trim();
    supabaseAnonKey = (json['supabaseAnonKey'] ?? '').toString().trim();
    webAppInviteBaseUrl = (json['webAppInviteBaseUrl'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
  }
}

