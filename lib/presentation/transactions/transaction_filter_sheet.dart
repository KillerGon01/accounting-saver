import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/transactions/amount_parser.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction_filter.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';
import 'formatters.dart';

/// Opens the search and filter panel over the visible month's
/// transactions (a `showModalBottomSheet`, not a fixed panel on the
/// screen: this way it takes up no space in the `body` while it
/// isn't open). Returns the new [TransactionFilter] if "Aplicar" or
/// "Limpiar" is pressed, or `null` if closed without choosing either
/// of the two (for example, by swiping the sheet down).
Future<TransactionFilter?> showTransactionFilterSheet(
  BuildContext context, {
  required TransactionFilter current,
}) {
  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TransactionFilterSheet(initial: current),
  );
}

class _TransactionFilterSheet extends StatefulWidget {
  const _TransactionFilterSheet({required this.initial});

  final TransactionFilter initial;

  @override
  State<_TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _searchController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  Category? _category;
  TransactionKind? _kind;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initial.searchText);
    _minController = TextEditingController(
      text: widget.initial.minAmountCents == null
          ? ''
          : formatEditableAmount(widget.initial.minAmountCents!),
    );
    _maxController = TextEditingController(
      text: widget.initial.maxAmountCents == null
          ? ''
          : formatEditableAmount(widget.initial.maxAmountCents!),
    );
    _category = widget.initial.categoryId;
    _kind = widget.initial.kind;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  int? _parseAmountField(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : parseEurosToCents(trimmed);
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return parseEurosToCents(text) == null ? 'Formato no válido, por ejemplo 12,50' : null;
  }

  String? _validateMax(String? value) {
    final ownError = _validateAmount(value);
    if (ownError != null) return ownError;

    final min = _parseAmountField(_minController.text);
    final max = _parseAmountField(value ?? '');
    if (min != null && max != null && min > max) {
      return 'El máximo no puede ser menor que el mínimo';
    }
    return null;
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TransactionFilter(
        searchText: _searchController.text,
        categoryId: _category,
        kind: _kind,
        minAmountCents: _parseAmountField(_minController.text),
        maxAmountCents: _parseAmountField(_maxController.text),
      ),
    );
  }

  void _clear() {
    Navigator.of(context).pop(TransactionFilter());
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.m,
        right: AppSpacing.m,
        top: AppSpacing.m,
        bottom: AppSpacing.m + viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buscar y filtrar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              TextFormField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar por concepto',
                  hintText: 'Por ejemplo: café',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: AppSpacing.m),
              DropdownButtonFormField<Category?>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  for (final category in Category.values)
                    DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(category.icon, color: category.color, size: 20),
                          const SizedBox(width: AppSpacing.s),
                          Flexible(
                            child: Text(category.label, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: AppSpacing.m),
              Text('Tipo', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<TransactionKind>(
                segments: const [
                  ButtonSegment(
                    value: TransactionKind.expense,
                    label: Text('Gasto'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: TransactionKind.income,
                    label: Text('Ingreso'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                ],
                selected: _kind == null ? const {} : {_kind!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) {
                  setState(() => _kind = selection.isEmpty ? null : selection.first);
                },
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                'Importe (sin signo): se combina con el tipo de arriba, no indiques el '
                'signo aquí.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(labelText: 'Mínimo', suffixText: '€'),
                      validator: _validateAmount,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: TextFormField(
                      controller: _maxController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(labelText: 'Máximo', suffixText: '€'),
                      validator: _validateMax,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.l),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clear,
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
