import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../auth/session_controller.dart';

/// One screen for both logging in and creating an account. It closes itself
/// when the session is signed in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.session,
    this.onSignedIn,
    this.initialRegistering = false,
  });

  final SessionController session;

  /// What to do once signed in. Without it the screen closes itself (it was pushed on top of another one).
  final VoidCallback? onSignedIn;

  /// Opens on "Create account" instead of "Log in".
  final bool initialRegistering;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  late bool _registering = widget.initialRegistering;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _registering = !_registering;
      _error = null;
    });
  }

  Future<void> _submit() async {
    // Set before the first await, so a second press while the request runs
    // finds the form busy and does nothing.
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    if (email.isEmpty || password.isEmpty || (_registering && displayName.isEmpty)) {
      setState(() => _error = 'Fill in every field');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await widget.session.register(
          email: email,
          displayName: displayName,
          password: password,
        );
      } else {
        await widget.session.login(email: email, password: password);
      }
      if (mounted) {
        final done = widget.onSignedIn;
        if (done != null) {
          done();
        } else {
          Navigator.of(context).pop();
        }
      }
    } on AuthApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _registering ? 'Create account' : 'Log in';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('emailField'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_registering)
            TextField(
              key: const Key('displayNameField'),
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          TextField(
            key: const Key('passwordField'),
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            key: const Key('submitButton'),
            onPressed: _busy ? null : _submit,
            child: Text(title),
          ),
          TextButton(
            key: const Key('switchModeButton'),
            onPressed: _busy ? null : _switchMode,
            child: Text(
              _registering
                  ? 'I already have an account'
                  : 'Create a new account',
            ),
          ),
        ],
      ),
    );
  }
}
