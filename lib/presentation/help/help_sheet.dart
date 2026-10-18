import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'help_content.dart';
import 'help_topic.dart';

/// Abre la hoja de ayuda de [topic] (ver `help_content.dart`). Mismo patrón
/// que el resto de hojas modales de la app (`TransactionFilterSheet`,
/// `SavingsSuggestionsSheet`): `isScrollControlled` para no desbordar con
/// el teclado, altura acotada y contenido siempre dentro de un
/// `SingleChildScrollView` para no desbordar con texto grande.
Future<void> showHelpSheet(BuildContext context, HelpTopic topic) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HelpSheet(topic: topic),
  );
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = helpContent[topic]!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, AppSpacing.m),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                entry.title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.m),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final step in entry.steps) ...[
                        _HelpStep(text: step),
                        const SizedBox(height: AppSpacing.s),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.circle, size: 6, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// Icono de ayuda reutilizable para el `AppBar` de cada pantalla: tooltip y
/// etiqueta semántica, siempre el mismo icono (`Icons.help_outline`).
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Ayuda',
      onPressed: () => showHelpSheet(context, topic),
      icon: const Icon(Icons.help_outline, semanticLabel: 'Ayuda'),
    );
  }
}
