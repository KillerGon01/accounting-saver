import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/savings/create_savings_goal.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/transactions/amount_parser.dart';
import '../common/firestore_error_messages.dart';
import '../transactions/formatters.dart';
import 'savings_goal_providers.dart';

/// Alta (sin [goal]) o edición (con [goal]) de una meta de ahorro: nombre,
/// importe objetivo y fecha límite. Lo ya ahorrado no se toca aquí —
/// `UpdateSavedAmountDialog` es la vía para eso (ver
/// `docs/design.md`, "Metas de ahorro").
class SavingsGoalFormScreen extends ConsumerStatefulWidget {
  const SavingsGoalFormScreen({super.key, required this.userId, this.goal});

  final String userId;
  final SavingsGoal? goal;

  @override
  ConsumerState<SavingsGoalFormScreen> createState() => _SavingsGoalFormScreenState();
}

class _SavingsGoalFormScreenState extends ConsumerState<SavingsGoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late DateTime _deadline;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _nameController = TextEditingController(text: goal?.name ?? '');
    _targetController = TextEditingController(
      text: goal == null ? '' : formatEditableAmount(goal.targetCents),
    );
    _deadline = goal?.deadline ?? DateTime.now().add(const Duration(days: 365));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline.isBefore(now) ? now : _deadline,
      firstDate: now,
      lastDate: DateTime(2200),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final targetCents = parseEurosToCents(_targetController.text)!;
    final existing = widget.goal;
    final goal = existing == null
        ? SavingsGoal(
            id: ref.read(savingsGoalRepositoryProvider).newId(userId: widget.userId),
            name: _nameController.text.trim(),
            targetCents: targetCents,
            savedCents: 0,
            deadline: _deadline,
            createdAt: DateTime.now(),
          )
        : existing.copyWith(
            name: _nameController.text.trim(),
            targetCents: targetCents,
            deadline: _deadline,
          );

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      if (_isEditing) {
        await ref.read(updateSavingsGoalProvider)(userId: widget.userId, goal: goal);
      } else {
        await ref.read(createSavingsGoalProvider)(userId: widget.userId, goal: goal);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        // `SavingsGoalLimitExceededException` ya es un mensaje en
        // español, pensado para mostrarse tal cual (no es un error crudo
        // de Firestore); cualquier otro error (permission-denied, red...)
        // se traduce a un mensaje genérico, nunca el error crudo.
        _errorMessage = error is SavingsGoalLimitExceededException
            ? error.toString()
            : firestoreErrorMessage(
                error,
                fallback: 'No se pudo guardar la meta. Inténtalo de nuevo más tarde.',
              );
      });
    }
  }

  String? _validateName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Introduce un nombre';
    if (text.length > SavingsGoal.maxNameLength) {
      return 'El nombre no puede superar los ${SavingsGoal.maxNameLength} caracteres';
    }
    return null;
  }

  String? _validateTarget(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Introduce un importe objetivo';
    final cents = parseEurosToCents(text);
    if (cents == null) return 'Formato no válido, por ejemplo 1.500,00';
    if (cents <= 0) return 'El importe objetivo debe ser mayor que 0';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar meta' : 'Nueva meta de ahorro')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    maxLength: SavingsGoal.maxNameLength,
                    decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Vacaciones'),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _targetController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: const InputDecoration(
                      labelText: 'Importe objetivo',
                      hintText: '1.500,00',
                      suffixText: '€',
                    ),
                    validator: _validateTarget,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Fecha límite: ${formatDate(_deadline)}'),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar'),
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
