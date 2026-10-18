import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth/app_user.dart';
import 'auth_error_messages.dart';
import 'auth_providers.dart';

const resendCooldownSeconds = 60;

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _cooldownTimer;
  int _secondsLeft = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    // The email is sent on sign-up, so the wait starts when the screen opens.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _secondsLeft = resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    await _run(() async {
      await ref.read(sendEmailVerificationProvider)();
      if (!mounted) return;
      _startCooldown();
      setState(() => _infoMessage = 'Te hemos enviado otro correo de verificación.');
    });
  }

  Future<void> _checkVerification() async {
    await _run(() async {
      final user = await ref.read(refreshEmailVerificationProvider)();
      if (!mounted) return;
      if (user.needsEmailVerification) {
        setState(() {
          _errorMessage =
              'Todavía no has verificado tu correo. Abre el enlace del correo e inténtalo de nuevo.';
        });
        return;
      }
      // AuthGate re-reads the session state and shows the transactions.
      ref.invalidate(authStateChangesProvider);
    });
  }

  Future<void> _signOut() async {
    // The only function shared by the app's three sign-out buttons
    // (see docs/design.md, "Avisos de sesión"): leaves `signedOut`
    // in `sessionFeedbackProvider` only if sign-out finishes
    // successfully.
    await _run(() => ref.read(signOutWithFeedbackProvider)());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = !_isLoading && _secondsLeft <= 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Hemos enviado un correo de verificación a ${widget.user.email ?? 'tu dirección'}.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Abre el enlace que contiene para activar tu cuenta y, después, '
                  'pulsa «Ya lo he verificado».',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Si no llega en unos minutos, revisa la carpeta de spam.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_infoMessage != null) ...[
                  Text(
                    _infoMessage!,
                    style: TextStyle(color: theme.colorScheme.primary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _isLoading ? null : _checkVerification,
                  child: const Text('Ya lo he verificado'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: canResend ? _resend : null,
                  child: Text(
                    _secondsLeft > 0
                        ? 'Reenviar correo (en $_secondsLeft s)'
                        : 'Reenviar correo',
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : _signOut,
                  child: const Text('Cerrar sesión / usar otro correo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
