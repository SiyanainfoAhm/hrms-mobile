import 'package:flutter/material.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _rpc = RpcService();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  String? _err;
  String? _ok;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      _busy = true;
      _err = null;
      _ok = null;
    });
    try {
      if (_next.text.trim().length < 8) {
        throw Exception('New password must be at least 8 characters.');
      }
      if (_next.text != _confirm.text) {
        throw Exception('New password and confirmation do not match.');
      }
      await _rpc.changePassword(
        userId: u.id,
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      setState(() {
        _ok = 'Password updated';
        _current.clear();
        _next.clear();
        _confirm.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final auth = u?.authProvider ?? 'password';
    final blocked = auth == 'google';

    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: ListView(
        padding: const EdgeInsets.all(HrmsTokens.s4),
        children: [
          if (blocked)
            const Text(
              'This account uses Google sign-in and has no password.',
              style: TextStyle(color: HrmsTokens.muted),
            )
          else ...[
            const Text(
              'Enter your current password, then a new one (at least 8 characters).',
              style: TextStyle(color: HrmsTokens.muted),
            ),
            const SizedBox(height: HrmsTokens.s4),
            TextField(
              controller: _current,
              decoration: const InputDecoration(hintText: 'Current password'),
              obscureText: true,
              enabled: !_busy,
            ),
            const SizedBox(height: HrmsTokens.s3),
            TextField(
              controller: _next,
              decoration: const InputDecoration(hintText: 'New password'),
              obscureText: true,
              enabled: !_busy,
            ),
            const SizedBox(height: HrmsTokens.s3),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(hintText: 'Confirm new password'),
              obscureText: true,
              enabled: !_busy,
            ),
            const SizedBox(height: HrmsTokens.s4),
            if (_err != null) Text(_err!, style: const TextStyle(color: HrmsTokens.danger)),
            if (_ok != null) Text(_ok!, style: const TextStyle(color: HrmsTokens.success)),
            const SizedBox(height: HrmsTokens.s3),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Updating…' : 'Update password'),
            ),
          ],
        ],
      ),
    );
  }
}

