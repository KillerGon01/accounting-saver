import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/transactions/parsed_transaction.dart';
import 'llm_error_messages.dart';
import 'transaction_providers.dart';

/// Field for adding a transaction by describing it in natural
/// language (for example "ayer 12,50 en el bar con Marta"). Only
/// parses the text: [onParsed] opens the already-filled form, and
/// nothing is saved until the user confirms it there.
class NaturalLanguageInput extends ConsumerStatefulWidget {
  const NaturalLanguageInput({super.key, required this.onParsed});

  static const maxLength = 300;

  final void Function(ParsedTransaction draft) onParsed;

  @override
  ConsumerState<NaturalLanguageInput> createState() => _NaturalLanguageInputState();
}

class _NaturalLanguageInputState extends ConsumerState<NaturalLanguageInput> {
  late final TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      final draft = await ref.read(parseNaturalLanguageTransactionProvider)(text: text);
      if (!mounted) return;
      _controller.clear();
      widget.onParsed(draft);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(llmErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _controller,
        maxLength: NaturalLanguageInput.maxLength,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Añadir con lenguaje natural',
          hintText: 'ayer 12,50 en el bar con Marta',
          border: const OutlineInputBorder(),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Interpretar con IA',
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: _submit,
                ),
        ),
      ),
    );
  }
}
