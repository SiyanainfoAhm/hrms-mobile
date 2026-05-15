import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/google_web_sso.dart';
import '../services/rpc_service.dart';

class SessionUser {
  SessionUser({
    required this.id,
    required this.email,
    required this.role,
    required this.name,
    required this.authProvider,
    required this.companyId,
  });

  final String id;
  final String email;
  final String role;
  final String? name;
  final String authProvider;
  final String? companyId;

  bool get isManagerial => role == 'super_admin' || role == 'admin' || role == 'hr';

  bool get isSuperAdmin => role == 'super_admin';

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'name': name,
        'authProvider': authProvider,
        'companyId': companyId,
      };

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        name: json['name']?.toString(),
        authProvider: (json['authProvider'] ?? 'password').toString(),
        companyId: json['companyId']?.toString(),
      );

  factory SessionUser.fromRpc(Map<String, dynamic> row) => SessionUser(
        id: (row['id'] ?? '').toString(),
        email: (row['email'] ?? '').toString(),
        role: (row['role'] ?? '').toString(),
        name: row['name']?.toString(),
        authProvider: (row['auth_provider'] ?? 'password').toString(),
        companyId: row['company_id']?.toString(),
      );
}

class AppState extends ChangeNotifier {
  AppState(this._rpc);

  final RpcService _rpc;

  SessionUser? user;
  bool loading = true;
  String? error;

  static const _kSessionKey = 'hrms_session_user';

  String _friendlyError(Object e) {
    if (e is PostgrestException) {
      final raw = '${e.message} ${e.details ?? ''}'.trim();
      if (_isAccountNotFoundMessage(raw)) return 'User does not exist';
      if (_isUserAlreadyExistsMessage(raw) || e.code == '23505') {
        return 'User already exists. Sign in instead or use a different email.';
      }
      if (e.message.trim().isNotEmpty) return e.message.trim();
      // Fallbacks by code are intentionally generic.
      if (e.code == '28000') return 'Invalid email or password.';
      return 'Request failed. Please try again.';
    }
    if (e is AuthException) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
      return 'Authentication failed. Please try again.';
    }
    if (e is StateError) {
      final msg = e.message.trim();
      if (_isAccountNotFoundMessage(msg)) return 'User does not exist';
      if (msg.isNotEmpty) return msg;
      return 'Something went wrong. Please try again.';
    }
    if (e is PlatformException && e.code == 'sign_in_failed') {
      final m = e.message ?? '';
      // Android: com.google.android.gms.common.api.ApiException: 10 = DEVELOPER_ERROR (SHA-1 / OAuth client).
      if (m.contains('ApiException: 10')) {
        return 'Google Sign-In is not registered for this Android app. In Google Cloud '
            'Console (same project as your Web client id), open Credentials → Create '
            'OAuth client ID → Android: package name com.siyanainfo.hrms_mobile, '
            'SHA-1 from signingReport for your debug or release keystore. Optionally '
            'put that Android client id in googleAndroidClientId in assets/config.json.';
      }
      final trimmed = m.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    final s = e.toString();
    if (_isAccountNotFoundMessage(s)) return 'User does not exist';
    if (_isUserAlreadyExistsMessage(s)) return 'User already exists. Sign in instead or use a different email.';
    if (s.contains('Invalid email or password')) return 'Invalid email or password.';
    return 'Something went wrong. Please try again.';
  }

  static bool _isAccountNotFoundMessage(String s) {
    final t = s.toLowerCase();
    return t.contains('account does not exist') ||
        t.contains('no account found') ||
        t.contains('user does not exist');
  }

  static bool _isUserAlreadyExistsMessage(String s) {
    final t = s.toLowerCase();
    return t.contains('user already exists') ||
        t.contains('email already registered') ||
        t.contains('already registered') ||
        t.contains('duplicate key') ||
        t.contains('unique constraint') ||
        t.contains('unique violation');
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> init() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionKey);
      if (raw != null && raw.isNotEmpty) {
        final restored = SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (restored.id.isNotEmpty) {
          user = restored;
        } else {
          await prefs.remove(_kSessionKey);
        }
      }
    } catch (e) {
      error = _friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.remove(_kSessionKey);
    } else {
      await prefs.setString(_kSessionKey, jsonEncode(user!.toJson()));
    }
  }

  Future<void> login(String email, String password) async {
    error = null;
    notifyListeners();
    try {
      final row = await _rpc.login(email, password);
      user = SessionUser.fromRpc(row);
      error = null;
      await _persist();
      notifyListeners();
    } catch (e) {
      error = _friendlyError(e);
      if (kDebugMode) {
        // ignore: avoid_print
        print('Login error: $e');
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Returns `true` if the user completed Google sign-in and a session was stored.
  /// Returns `false` if the user closed the account picker (no error).
  Future<bool> loginWithGoogle() async {
    error = null;
    notifyListeners();
    if (!GoogleWebSso.isConfigured) {
      error =
          'Google sign-in is not configured. Set webAppInviteBaseUrl and googleWebClientId in assets/config.json (same values as hrms-web).';
      notifyListeners();
      throw StateError(error!);
    }
    try {
      final idToken = await GoogleWebSso.obtainIdToken();
      if (idToken == null || idToken.isEmpty) {
        error = null;
        notifyListeners();
        return false;
      }
      final session = await GoogleWebSso.postVerify(idToken: idToken);
      final id = session['id']?.toString() ?? '';
      if (id.isEmpty) {
        throw StateError('Invalid account response.');
      }
      final me = await _rpc.me(id);
      if (me == null) {
        throw StateError('Could not load your profile.');
      }
      user = SessionUser.fromRpc(me);
      error = null;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      error = _friendlyError(e);
      if (kDebugMode) {
        // ignore: avoid_print
        print('Google login error: $e');
      }
      notifyListeners();
      // Let the user pick a different Google account on the next attempt (e.g. after "User does not exist").
      try {
        await GoogleWebSso.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  /// Returns `true` if signup completed. Returns `false` if the user dismissed Google (no error).
  Future<bool> signupWithGoogle({required String companyName}) async {
    error = null;
    notifyListeners();
    if (!GoogleWebSso.isConfigured) {
      error =
          'Google sign-in is not configured. Set webAppInviteBaseUrl and googleWebClientId in assets/config.json (same values as hrms-web).';
      notifyListeners();
      throw StateError(error!);
    }
    final co = companyName.trim();
    if (co.isEmpty) {
      error = 'Company name is required.';
      notifyListeners();
      throw StateError(error!);
    }
    try {
      final idToken = await GoogleWebSso.obtainIdToken();
      if (idToken == null || idToken.isEmpty) {
        error = null;
        notifyListeners();
        return false;
      }
      final session = await GoogleWebSso.postVerify(idToken: idToken, signup: true, companyName: co);
      final id = session['id']?.toString() ?? '';
      if (id.isEmpty) {
        throw StateError('Invalid account response.');
      }
      final me = await _rpc.me(id);
      if (me == null) {
        throw StateError('Could not load your profile.');
      }
      user = SessionUser.fromRpc(me);
      error = null;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      error = _friendlyError(e);
      if (kDebugMode) {
        // ignore: avoid_print
        print('Google signup error: $e');
      }
      notifyListeners();
      try {
        await GoogleWebSso.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> signup(String email, String password, {String? name, required String companyName}) async {
    error = null;
    notifyListeners();
    try {
      final row = await _rpc.signup(email, password, name: name, companyName: companyName);
      user = SessionUser.fromRpc(row);
      error = null;
      await _persist();
      notifyListeners();
    } catch (e) {
      error = _friendlyError(e);
      if (kDebugMode) {
        // ignore: avoid_print
        print('Signup error: $e');
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    await GoogleWebSso.signOut();
    user = null;
    await _persist();
    notifyListeners();
  }

  /// After profile RPC save, refresh session fields (name, company) from row.
  Future<void> applyProfileRow(Map<String, dynamic> row) async {
    final u = user;
    if (u == null) return;
    user = SessionUser(
      id: u.id,
      email: u.email,
      role: u.role,
      name: row['name']?.toString() ?? u.name,
      authProvider: u.authProvider,
      companyId: row['company_id']?.toString() ?? u.companyId,
    );
    await _persist();
    notifyListeners();
  }
}

