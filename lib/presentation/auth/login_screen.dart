import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAndPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(signInWithEmailAndPasswordProvider)(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (error) {
      setState(() => _errorMessage = 'No se pudo iniciar sesión: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(signInWithGoogleProvider)();
    } catch (error) {
      setState(
        () => _errorMessage = 'No se pudo iniciar sesión con Google: $error',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
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
                    style: Theme.of(context).textTheme.headlineMedium,
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
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Introduce tu correo electrónico';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Introduce tu contraseña';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _submitGoogleSignIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Continuar con Google'),
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
