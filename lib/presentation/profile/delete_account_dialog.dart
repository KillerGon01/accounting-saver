import 'package:flutter/material.dart';

/// Resultado del diálogo cuando el usuario confirma. [password] solo viene
/// informado con correo y contraseña.
class DeleteAccountRequest {
  const DeleteAccountRequest({this.password});

  final String? password;
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({
    required this.email,
    required this.requiresPassword,
    super.key,
  });

  final String email;
  final bool requiresPassword;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_refresh);
    _passwordController.addListener(_refresh);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// El correo debe coincidir exactamente, sin recortar ni ignorar mayúsculas.
  bool get _canConfirm {
    if (widget.email.isEmpty || _emailController.text != widget.email) return false;
    return !widget.requiresPassword || _passwordController.text.isNotEmpty;
  }

  void _confirm() {
    Navigator.of(context).pop(
      DeleteAccountRequest(
        password: widget.requiresPassword ? _passwordController.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Eliminar cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Se borrarán tu cuenta y TODOS tus movimientos. '
              'Esta acción no se puede deshacer.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            Text('Para confirmar, escribe tu correo electrónico: ${widget.email}'),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Correo electrónico'),
            ),
            if (widget.requiresPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Para confirmar que eres tú',
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              const Text('Se te pedirá confirmar con tu cuenta de Google.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _canConfirm ? _confirm : null,
          child: const Text('Eliminar definitivamente'),
        ),
      ],
    );
  }
}
