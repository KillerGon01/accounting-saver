import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_error_messages.dart';
import 'auth_providers.dart';
import 'auth_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  // Visibilidad local de cada campo. Por defecto, oculta.
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Los iconos no toman el foco: así el campo conserva el cursor al pulsarlos.
  final _passwordToggleFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  final _confirmToggleFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordToggleFocusNode.dispose();
    _confirmToggleFocusNode.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _errorMessage = null;
      _infoMessage = null;
      _obscurePassword = true;
      _obscureConfirmPassword = true;
    });
  }

  Widget _visibilityToggle({
    required bool obscured,
    required FocusNode focusNode,
    required VoidCallback onPressed,
  }) {
    final tooltip = obscured ? 'Mostrar contraseña' : 'Ocultar contraseña';
    return IconButton(
      focusNode: focusNode,
      tooltip: tooltip,
      icon: Icon(
        obscured ? Icons.visibility : Icons.visibility_off,
        semanticLabel: tooltip,
      ),
      onPressed: onPressed,
    );
  }

  Future<void> _submitEmailAndPassword() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    await _run(() async {
      if (_isRegisterMode) {
        await ref.read(signUpWithEmailAndPasswordProvider)(
          email: email,
          password: password,
        );
      } else {
        await ref.read(signInWithEmailAndPasswordProvider)(
          email: email,
          password: password,
        );
      }
    });
  }

  Future<void> _submitGoogleSignIn() async {
    await _run(() async {
      await ref.read(signInWithGoogleProvider)();
    });
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    final emailError = validateEmail(email);
    if (emailError != null) {
      setState(() {
        _errorMessage = emailError;
        _infoMessage = null;
      });
      return;
    }

    await _run(() async {
      await ref.read(sendPasswordResetEmailProvider)(email: email);
      if (mounted) {
        setState(() {
          _infoMessage =
              'Si existe una cuenta con ese correo, te hemos enviado un enlace '
              'para restablecer la contraseña.';
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Crear cuenta' : 'Iniciar sesión'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Accounting Saver',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                    validator: validateEmail,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: [
                      _isRegisterMode
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: _isRegisterMode
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onFieldSubmitted: _isRegisterMode
                        ? null
                        : (_) => _submitEmailAndPassword(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      helperText: _isRegisterMode
                          ? 'Mínimo $minPasswordLength caracteres'
                          : null,
                      suffixIcon: _visibilityToggle(
                        obscured: _obscurePassword,
                        focusNode: _passwordToggleFocusNode,
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: _isRegisterMode
                        ? validateNewPassword
                        : validateLoginPassword,
                  ),
                  if (_isRegisterMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitEmailAndPassword(),
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        suffixIcon: _visibilityToggle(
                          obscured: _obscureConfirmPassword,
                          focusNode: _confirmToggleFocusNode,
                          onPressed: () => setState(
                            () => _obscureConfirmPassword = !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                      validator: (value) => validateConfirmPassword(
                        value,
                        _passwordController.text,
                      ),
                    ),
                  ] else
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: _isLoading ? null : _sendPasswordReset,
                        child: const Text('¿Has olvidado la contraseña?'),
                      ),
                    ),
                  const SizedBox(height: 16),
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
                    onPressed: _isLoading ? null : _submitEmailAndPassword,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isRegisterMode ? 'Crear cuenta' : 'Entrar'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _submitGoogleSignIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Continuar con Google'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    child: Text(
                      _isRegisterMode
                          ? '¿Ya tienes cuenta? Iniciar sesión'
                          : '¿No tienes cuenta? Crear cuenta',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
