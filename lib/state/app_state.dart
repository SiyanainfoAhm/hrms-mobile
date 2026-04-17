import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
      // Fallbacks by code are intentionally generic.
      if (e.code == '28000') return 'Invalid email or password.';
      return 'Request failed. Please try again.';
    }
    if (e is AuthException) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
      return 'Authentication failed. Please try again.';
    }
    final s = e.toString();
    if (s.contains('Invalid email or password')) return 'Invalid email or password.';
    return 'Something went wrong. Please try again.';
  }

  Future<void> init() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionKey);
      if (raw != null && raw.isNotEmpty) {
        user = SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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

  Future<void> signup(String email, String password, {String? name}) async {
    error = null;
    notifyListeners();
    try {
      final row = await _rpc.signup(email, password, name: name);
      user = SessionUser.fromRpc(row);
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

