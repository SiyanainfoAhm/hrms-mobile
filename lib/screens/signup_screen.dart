import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/google_web_sso.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/hrms_auth_shell.dart';

enum _SignupKind { emailPassword, google }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  final companyName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  _SignupKind _kind = _SignupKind.emailPassword;
  bool busy = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  bool get _companyOk => companyName.text.trim().isNotEmpty;

  bool get _emailPasswordReady {
    if (!_companyOk) return false;
    if (email.text.trim().isEmpty) return false;
    if (password.text.length < 6) return false;
    if (password.text != confirm.text) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.app.clearError();
    });
  }

  @override
  void dispose() {
    name.dispose();
    companyName.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: HrmsTokens.success,
      ),
    );
  }

  Future<void> submit() async {
    if (password.text != confirm.text) {
      setState(() {});
      return;
    }
    final co = companyName.text.trim();
    if (co.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company name is required')),
        );
      }
      return;
    }
    setState(() => busy = true);
    try {
      await widget.app.signup(
        email.text.trim(),
        password.text,
        name: name.text.trim().isEmpty ? null : name.text.trim(),
        companyName: co,
      );
      if (!mounted) return;
      _showSuccess('Account created successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      // error shown from app.error
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _googleSignup() async {
    final co = companyName.text.trim();
    if (co.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company name is required')),
        );
      }
      return;
    }
    setState(() => busy = true);
    try {
      final ok = await widget.app.signupWithGoogle(companyName: co);
      if (!mounted) return;
      if (!ok) return;
      _showSuccess('Account created successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      // error shown from app.error
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _clearAppErrorIfNeeded() {
    if (widget.app.error != null) {
      widget.app.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mismatch = password.text.isNotEmpty && confirm.text.isNotEmpty && password.text != confirm.text;
    final googleConfigured = GoogleWebSso.isConfigured;
    final createEnabled = !busy && _kind == _SignupKind.emailPassword && _emailPasswordReady;
    final googleEnabled = !busy && _kind == _SignupKind.google && _companyOk && googleConfigured;

    return HrmsAuthShell(
      title: 'Create your account',
      subtitle: 'Enter your company first, then sign up with email or Google.',
      child: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final err = widget.app.error;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: companyName,
                decoration: const InputDecoration(
                  labelText: 'Company name',
                  hintText: 'Required for all signups',
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  _clearAppErrorIfNeeded();
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<_SignupKind>(
                segments: const [
                  ButtonSegment<_SignupKind>(
                    value: _SignupKind.emailPassword,
                    label: Text('Email & password'),
                  ),
                  ButtonSegment<_SignupKind>(
                    value: _SignupKind.google,
                    label: Text('Google'),
                  ),
                ],
                selected: <_SignupKind>{_kind},
                onSelectionChanged: (Set<_SignupKind> next) {
                  widget.app.clearError();
                  setState(() => _kind = next.first);
                },
              ),
              const SizedBox(height: 16),
              if (_kind == _SignupKind.emailPassword) ...[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'Optional',
                  ),
                  onChanged: (_) => _clearAppErrorIfNeeded(),
                ),
                const SizedBox(height: 12),
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                        onChanged: (_) {
                          _clearAppErrorIfNeeded();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: !_passwordVisible,
                        obscuringCharacter: '•',
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        enableIMEPersonalizedLearning: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Password (min. 6 characters)',
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                            icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          ),
                        ),
                        onChanged: (_) {
                          _clearAppErrorIfNeeded();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirm,
                        obscureText: !_confirmPasswordVisible,
                        obscuringCharacter: '•',
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        enableIMEPersonalizedLearning: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          errorText: mismatch ? 'Passwords do not match' : null,
                          suffixIcon: IconButton(
                            tooltip: _confirmPasswordVisible ? 'Hide password' : 'Show password',
                            onPressed: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                            icon: Icon(_confirmPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          ),
                        ),
                        onChanged: (_) {
                          _clearAppErrorIfNeeded();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ] else ...[
              ],
              const SizedBox(height: 16),
              if (err != null && err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    err,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                  ),
                ),
              if (_kind == _SignupKind.emailPassword)
                FilledButton(
                  onPressed: createEnabled ? submit : null,
                  child: Text(busy ? 'Creating…' : 'Create account'),
                )
              else
                FilledButton.tonal(
                  onPressed: googleEnabled ? _googleSignup : null,
                  child: Text(busy ? 'Please wait…' : 'Continue with Google'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        widget.app.clearError();
                        context.go('/login');
                      },
                child: const Text('Already have an account? Log in'),
              ),
            ],
          );
        },
      ),
    );
  }
}
