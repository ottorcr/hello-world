import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/repository.dart';
import 'common.dart';

/// Email + password sign in / sign up.
///
/// We deliberately don't offer Google/Facebook login. Apple then requires
/// nothing extra (guideline 4.8), and no third-party tracking SDK is added.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_creating) {
        if (_password.text.length < 8) {
          throw FirebaseAuthException(
            code: 'weak-password',
            message: 'Use at least 8 characters for your password.',
          );
        }
        final cred = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await cred.user?.sendEmailVerification();
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Type your email first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      // Don't reveal whether the address has an account.
    }
    if (mounted) {
      toast(
        context,
        'If that email has an account, a reset link is on its way.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '💭',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Random Thoughts',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Little thoughts from your friends, right on your home screen. '
                      'Only friends you approve can send you anything.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _creating
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        errorMaxLines: 3,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_creating ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _creating = !_creating;
                              _error = null;
                            }),
                      child: Text(
                        _creating
                            ? 'I already have an account'
                            : 'New here? Create an account',
                      ),
                    ),
                    if (!_creating)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _authMessage(FirebaseAuthException e) => switch (e.code) {
  'invalid-email' => 'That email doesn’t look right.',
  'email-already-in-use' =>
    'That email already has an account. Sign in instead.',
  'weak-password' => e.message ?? 'Pick a stronger password.',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'Wrong email or password.',
  'too-many-requests' => 'Too many tries. Wait a bit and try again.',
  'network-request-failed' => 'No connection. Check your internet.',
  _ => e.message ?? 'Something went wrong (${e.code}).',
};

/// Shown until the user clicks the link in the verification email.
/// The security rules refuse writes from unverified accounts.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.user});

  final User user;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    await widget.user.reload();
    if (FirebaseAuth.instance.currentUser?.emailVerified ?? false) {
      // Refresh the ID token so the security rules see email_verified.
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      _poll?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check your email'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: MessageView(
        icon: Icons.mark_email_unread_outlined,
        text:
            'We sent a link to ${widget.user.email}.\n'
            'Tap it to verify your email, then come back here.',
        action: OutlinedButton(
          onPressed: () async {
            await widget.user.sendEmailVerification();
            if (context.mounted) toast(context, 'Sent again.');
          },
          child: const Text('Resend email'),
        ),
      ),
    );
  }
}

/// One-time setup: display name, age confirmation, privacy policy.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.repo});

  final Repository repo;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  bool _oldEnough = false;
  bool _agreed = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.repo.createProfile(_name.text);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _name.text.trim().isNotEmpty && _oldEnough && _agreed && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Almost there')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('What should your friends call you?'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: AppConfig.maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _oldEnough,
            onChanged: (v) => setState(() => _oldEnough = v ?? false),
            title: Text('I am ${AppConfig.minimumAge} or older'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: const Text('I agree to the privacy policy'),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () =>
                    launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
                child: const Text('Read it'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ready ? _save : null,
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
