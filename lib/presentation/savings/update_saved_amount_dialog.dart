import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/savings/savings_goal.dart';
import '../../domain/transactions/amount_parser.dart';
import '../transactions/formatters.dart';

/// Diálogo para actualizar lo ahorrado de [goal] a un importe nuevo (no
/// un incremento: el valor absoluto). Devuelve los céntimos nuevos, o
/// `null` si se cancela.
Future<int?> showUpdateSavedAmountDialog(BuildContext context, SavingsGoal goal) {
  return showDialog<int>(
    context: context,
    builder: (context) => _UpdateSavedAmountDialog(goal: goal),
  );
}

class _UpdateSavedAmountDialog extends StatefulWidget {
  const _UpdateSavedAmountDialog({required this.goal});

  final SavingsGoal goal;

  @override
  State<_UpdateSavedAmountDialog> createState() => _UpdateSavedAmountDialogState();
}

class _UpdateSavedAmountDialogState extends State<_UpdateSavedAmountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatEditableAmount(widget.goal.savedCents));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Introduce un importe';
    final cents = parseEurosToCents(text);
    if (cents == null) return 'Formato no válido, por ejemplo 250,00';
    if (cents < 0) return 'Lo ahorrado no puede ser negativo';
    return null;
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(parseEurosToCents(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualizar lo ahorrado'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Ahorrado hasta ahora',
            hintText: '250,00',
            suffixText: '€',
            helperText: 'Objetivo: ${formatCents(widget.goal.targetCents)}',
          ),
          validator: _validate,
          onFieldSubmitted: (_) => _confirm(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirm, child: const Text('Guardar')),
      ],
    );
  }
}
