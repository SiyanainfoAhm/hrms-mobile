import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/google_web_sso.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/auth_or_divider.dart';
import '../widgets/hrms_auth_shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  void dispose() {
    name.dispose();
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
    setState(() => busy = true);
    try {
      await widget.app.signup(
        email.text.trim(),
        password.text,
        name: name.text.trim().isEmpty ? null : name.text.trim(),
      );
      if (!mounted) return;
      _showSuccess('Account created successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/dashboard');
    } catch (_) {
      // error shown from app.error
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _googleSignup() async {
    setState(() => busy = true);
    try {
      await widget.app.loginWithGoogle(isSignup: true);
      if (!mounted) return;
      _showSuccess('Signed in successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/dashboard');
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
    return HrmsAuthShell(
      title: 'Create your account',
      subtitle: 'Use your work email to get started. You can finish your profile later.',
      child: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final err = widget.app.error;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
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
                      onChanged: (_) => _clearAppErrorIfNeeded(),
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
                        labelText: 'Password',
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
              const SizedBox(height: 16),
              if (err != null && err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    err,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Creating…' : 'Create account'),
              ),
              if (GoogleWebSso.isConfigured) ...[
                const AuthOrDivider(),
                OutlinedButton(
                  onPressed: busy ? null : _googleSignup,
                  child: Text(busy ? 'Please wait…' : 'Continue with Google'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy ? null : () => context.go('/login'),
                child: const Text('Already have an account? Log in'),
              ),
            ],
          );
        },
      ),
    );
  }
}
