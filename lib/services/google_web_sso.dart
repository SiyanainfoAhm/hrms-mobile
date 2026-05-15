import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'runtime_config.dart';

/// Same flow as hrms-web [GoogleAuthButton] + `/api/auth/google`: obtain a Google ID token,
/// verify it on the deployed web app, then the mobile app loads the user via Supabase `hrms_me`.
class GoogleWebSso {
  static GoogleSignIn? _googleSignIn;

  static bool get isConfigured {
    final c = RuntimeConfig.instance;
    return c.webAppInviteBaseUrl.isNotEmpty && c.googleWebClientId.isNotEmpty;
  }

  static GoogleSignIn _client(RuntimeConfig c) {
    _googleSignIn ??= GoogleSignIn(
      scopes: const <String>['email', 'openid'],
      serverClientId: c.googleWebClientId.isEmpty ? null : c.googleWebClientId,
      clientId: _nativeOAuthClientId(c),
    );
    return _googleSignIn!;
  }

  /// iOS / Android OAuth client ids from Google Cloud (different from [RuntimeConfig.googleWebClientId]).
  /// Android: if null, Play Services expects `google-services.json` or a matching Android OAuth client
  /// registered with your app package + SHA-1 (otherwise `ApiException: 10` / DEVELOPER_ERROR).
  static String? _nativeOAuthClientId(RuntimeConfig c) {
    if (kIsWeb) return null;
    try {
      if (Platform.isIOS && c.googleIosClientId.isNotEmpty) return c.googleIosClientId;
      if (Platform.isAndroid && c.googleAndroidClientId.isNotEmpty) return c.googleAndroidClientId;
    } on UnsupportedError {
      // Non-IO platforms when dart:io is stubbed.
    } catch (_) {}
    return null;
  }

  /// Returns an ID token suitable for [postVerify], or `null` if the user closed the picker.
  static Future<String?> obtainIdToken() async {
    final c = RuntimeConfig.instance;
    if (!isConfigured) {
      throw StateError('Google sign-in is not configured.');
    }
    final client = _client(c);
    // Android (and sometimes iOS) reuses the last account without showing the chooser.
    // Signing out first clears the in-app Google session so the user can pick an account.
    try {
      await client.signOut();
    } catch (_) {
      // ignore
    }
    final account = await client.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final token = auth.idToken;
    if (token == null || token.isEmpty) {
      await signOut();
      throw StateError(
        'Google did not return an ID token. Use the same Web client id as hrms-web '
        '`NEXT_PUBLIC_GOOGLE_CLIENT_ID` in `googleWebClientId`. On iOS, set '
        '`googleIosClientId` and CFBundleURLSchemes (reversed client id) in Info.plist. '
        'On Android, register package com.siyanainfo.hrms_mobile + SHA-1 in Google Cloud '
        '(Android OAuth client) or set `googleAndroidClientId` in assets/config.json.',
      );
    }
    return token;
  }

  /// Calls hrms-web `POST /api/auth/google`. [signup] + [companyName] creates org + user (mobile signup); otherwise existing users only.
  static Future<Map<String, dynamic>> postVerify({
    required String idToken,
    bool signup = false,
    String? companyName,
  }) async {
    final base = RuntimeConfig.instance.webAppInviteBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/auth/google');
    final payload = <String, dynamic>{
      'idToken': idToken,
      'mode': signup ? 'signup' : 'login',
    };
    final co = companyName?.trim() ?? '';
    if (co.isNotEmpty) {
      payload['companyName'] = co;
    }
    final res = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Google sign-in failed (HTTP ${res.statusCode}).');
    }
    if (res.statusCode != 200) {
      final msg = (body['error'] ?? '').toString().trim();
      throw StateError(msg.isNotEmpty ? msg : 'Google sign-in failed.');
    }
    final u = body['user'];
    if (u is! Map) {
      throw StateError('Invalid server response.');
    }
    return Map<String, dynamic>.from(u);
  }

  static Future<void> signOut() async {
    await _googleSignIn?.signOut();
  }
}
