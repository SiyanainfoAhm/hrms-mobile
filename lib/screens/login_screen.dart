import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/google_web_sso.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/auth_or_divider.dart';
import '../widgets/hrms_auth_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.app});

  final AppState app;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.app.clearError();
    });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
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

  void _clearError() {
    widget.app.clearError();
  }

  Future<void> submit() async {
    _clearError();
    setState(() => busy = true);
    try {
      await widget.app.login(email.text.trim(), password.text);
      if (!mounted) return;
      _showSuccess('Signed in successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      // error shown from app.error via ListenableBuilder
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _googleLogin() async {
    _clearError();
    setState(() => busy = true);
    try {
      final ok = await widget.app.loginWithGoogle();
      if (!mounted) return;
      if (!ok) return;
      _showSuccess('Signed in successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      // error shown from app.error
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleFirst = GoogleWebSso.isConfigured;
    return HrmsAuthShell(
      title: 'Welcome back',
      subtitle: googleFirst
          ? 'Sign in if you already have HRMS access (Google or email below). To create a new company account, use Sign up.'
          : 'Sign in with your work email and password.',
      child: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final err = widget.app.error;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (googleFirst) ...[
                OutlinedButton(
                  onPressed: busy ? null : _googleLogin,
                  child: Text(busy ? 'Please wait…' : 'Continue with Google'),
                ),
                const AuthOrDivider(),
              ],
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
                      onTap: _clearError,
                      onChanged: (_) {
                        if (widget.app.error != null) _clearError();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: !_passwordVisible,
                      obscuringCharacter: '•',
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      enableIMEPersonalizedLearning: false,
                      autofillHints: const [AutofillHints.password],
                      onTap: _clearError,
                      onSubmitted: (_) => submit(),
                      onChanged: (_) {
                        if (widget.app.error != null) _clearError();
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
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
                child: Text(busy ? 'Signing in…' : 'Sign in'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        _clearError();
                        context.go('/signup');
                      },
                child: const Text("Don't have an account? Sign up"),
              ),
            ],
          );
        },
      ),
    );
  }
}
