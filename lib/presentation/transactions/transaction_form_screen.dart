import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/transactions/amount_parser.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/parsed_transaction.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_source.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';
import 'formatters.dart';
import 'transaction_providers.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    required this.userId,
    this.transaction,
    this.initialDraft,
  });

  final String userId;

  /// Movimiento existente a editar.
  final Transaction? transaction;

  /// Propuesta de la IA para un movimiento nuevo, pendiente de confirmar.
  /// Se ignora si [transaction] no es `null`.
  final ParsedTransaction? initialDraft;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late bool _isExpense;
  late DateTime _date;
  Category? _category;
  bool _isSaving = false;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    final draft = widget.initialDraft;
    final amountCents = transaction?.amountCents.abs() ?? draft?.amountCents.abs();
    _amountController = TextEditingController(
      text: amountCents == null ? '' : formatEditableAmount(amountCents),
    );
    _descriptionController = TextEditingController(
      text: transaction?.description ?? draft?.description,
    );
    _isExpense = transaction?.isExpense ?? draft?.isExpense ?? true;
    _date = transaction?.date ?? draft?.date ?? _today();
    _category = transaction?.categoryId ?? draft?.categoryId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final absoluteCents = parseEurosToCents(_amountController.text)!;
    final transaction = Transaction(
      id: widget.transaction?.id ??
          ref.read(transactionRepositoryProvider).newId(userId: widget.userId),
      amountCents: _isExpense ? -absoluteCents : absoluteCents,
      date: _date,
      description: _descriptionController.text.trim(),
      categoryId: _category!,
      source: widget.transaction?.source ??
          (widget.initialDraft != null ? TransactionSource.naturalLanguage : TransactionSource.manual),
      createdAt: widget.transaction?.createdAt ?? DateTime.now(),
    );

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ref.read(updateTransactionProvider)(
          userId: widget.userId,
          transaction: transaction,
        );
      } else {
        await ref.read(addTransactionProvider)(
          userId: widget.userId,
          transaction: transaction,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el movimiento: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((_isEditing, widget.initialDraft != null)) {
          (true, _) => 'Editar movimiento',
          (false, true) => 'Confirmar movimiento',
          (false, false) => 'Nuevo movimiento',
        }),
      ),
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
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Gasto'),
                        icon: Icon(Icons.arrow_downward),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Ingreso'),
                        icon: Icon(Icons.arrow_upward),
                      ),
                    ],
                    selected: {_isExpense},
                    onSelectionChanged: (selection) =>
                        setState(() => _isExpense = selection.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Importe',
                      hintText: '12,50',
                      suffixText: '€',
                    ),
                    validator: _validateAmount,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Fecha: ${formatDate(_date)}'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLength: Transaction.maxDescriptionLength,
                    decoration: const InputDecoration(labelText: 'Concepto'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Introduce un concepto';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Category>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: [
                      for (final category in Category.values)
                        DropdownMenuItem(
                          value: category,
                          child: Row(
                            children: [
                              Icon(category.icon, color: category.color, size: 20),
                              const SizedBox(width: AppSpacing.s),
                              Text(category.label),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _category = value),
                    validator: (value) =>
                        value == null ? 'Selecciona una categoría' : null,
                  ),
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

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Introduce un importe';
    final cents = parseEurosToCents(text);
    if (cents == null) return 'Formato no válido, por ejemplo 12,50';
    if (cents <= 0) return 'El importe debe ser mayor que 0';
    return null;
  }
}
