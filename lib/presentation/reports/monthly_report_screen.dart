import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_check_config.dart';
import '../../domain/reports/monthly_report.dart';
import '../common/firestore_error_messages.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import '../transactions/transaction_providers.dart';
import 'category_bar_chart.dart';
import 'report_error_messages.dart';
import 'report_formatters.dart';
import 'report_providers.dart';

const _slowReplyWarningDelay = Duration(seconds: 10);
const _verySlowReplyWarningDelay = Duration(seconds: 45);

/// Pantalla de resumen mensual: totales, gasto por categoría, comparación
/// con el mes anterior y, si [showAiComment] lo permite, un comentario de
/// la IA sobre esas mismas cifras.
///
/// [showAiComment] es opcional y por defecto toma [effectiveEnableAi] (lo
/// mismo que ya decide si se muestran el chat o la entrada en lenguaje
/// natural): solo existe como parámetro para poder probar en los tests
/// la pantalla con y sin la sección de IA sin depender de con qué
/// `--dart-define=ENABLE_AI` se haya lanzado `flutter test`.
class MonthlyReportScreen extends ConsumerStatefulWidget {
  MonthlyReportScreen({super.key, required this.userId, bool? showAiComment})
    : showAiComment = showAiComment ?? effectiveEnableAi;

  final String userId;
  final bool showAiComment;

  @override
  ConsumerState<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  late DateTime _selectedMonth;
  String? _comment;
  bool _isGenerating = false;
  int? _remainingComments;
  Timer? _slowReplyTimer;
  Timer? _verySlowReplyTimer;
  bool _isSlowReply = false;
  bool _isVerySlowReply = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _remainingComments = ref.read(explainMonthlyReportProvider(widget.userId)).remainingComments;
  }

  @override
  void dispose() {
    _slowReplyTimer?.cancel();
    _verySlowReplyTimer?.cancel();
    super.dispose();
  }

  bool get _isCurrentMonthSelected {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
      _comment = null;
      _isSlowReply = false;
      _isVerySlowReply = false;
    });
  }

  Future<void> _generateComment(MonthlyReport report) async {
    setState(() {
      _isGenerating = true;
      _isSlowReply = false;
      _isVerySlowReply = false;
    });

    // Timers, no un `Future.delayed` esperado: no bloquean nada (mismo
    // patrón que `ChatScreen`).
    _slowReplyTimer = Timer(_slowReplyWarningDelay, () {
      if (!mounted || !_isGenerating) return;
      setState(() => _isSlowReply = true);
    });
    _verySlowReplyTimer = Timer(_verySlowReplyWarningDelay, () {
      if (!mounted || !_isGenerating) return;
      setState(() => _isVerySlowReply = true);
    });

    try {
      final comment = await ref.read(explainMonthlyReportProvider(widget.userId))(report: report);
      if (!mounted) return;
      setState(() => _comment = comment);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportErrorMessage(error))));
    } finally {
      _slowReplyTimer?.cancel();
      _verySlowReplyTimer?.cancel();
      final remaining = ref.read(explainMonthlyReportProvider(widget.userId)).remainingComments;
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _remainingComments = remaining;
        });
      }
    }
  }

  String get _progressMessage {
    final parts = ['Generando el comentario...'];
    if (_isSlowReply) parts.add('Esto está tardando más de lo normal...');
    if (_isVerySlowReply) parts.add('Puede tardar hasta un par de minutos.');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = MonthlyTransactionsParams(
      userId: widget.userId,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
    );
    final reportAsync = ref.watch(monthlyReportProvider(params));

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen del mes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.s),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        formatMonth(_selectedMonth),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: _isCurrentMonthSelected ? null : () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: reportAsync.when(
                  data: (report) => _ReportBody(
                    report: report,
                    showAiComment: widget.showAiComment,
                    comment: _comment,
                    isGenerating: _isGenerating,
                    progressMessage: _progressMessage,
                    remainingComments: _remainingComments ?? 0,
                    onGenerateComment: () => _generateComment(report),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Text(
                        firestoreErrorMessage(
                          error,
                          fallback: 'No se pudo calcular el resumen. Inténtalo de nuevo más tarde.',
                        ),
                      ),
                    ),
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

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.showAiComment,
    required this.comment,
    required this.isGenerating,
    required this.progressMessage,
    required this.remainingComments,
    required this.onGenerateComment,
  });

  final MonthlyReport report;
  final bool showAiComment;
  final String? comment;
  final bool isGenerating;
  final String progressMessage;
  final int remainingComments;
  final VoidCallback onGenerateComment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final balanceColor = report.balanceCents < 0 ? finance.expense : finance.income;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        if (report.isCurrentMonth)
          _InfoBanner(
            icon: Icons.schedule,
            text: 'Mes en curso, hasta el día ${report.elapsedDays}.',
          ),
        if (report.truncated)
          const _InfoBanner(
            icon: Icons.warning_amber_outlined,
            text: 'Informe parcial: se han leído los primeros 2.000 movimientos de este rango.',
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Balance del mes', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  formatCents(report.balanceCents),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: balanceColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryTile(
                        label: 'Ingresos',
                        value: formatCents(report.incomeCents),
                        color: finance.income,
                      ),
                    ),
                    Expanded(
                      child: _SummaryTile(
                        label: 'Gastos',
                        value: formatCents(report.expenseCents),
                        color: finance.expense,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${report.transactionCount} movimientos',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Gasto por categoría', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.s),
                CategoryBarChart(categories: report.categoryBreakdown),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Comparación con el mes anterior', style: theme.textTheme.labelLarge),
                    if (report.isCurrentMonth && report.comparison != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '(parcial, mes en curso)',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                _ComparisonBody(comparison: report.comparison),
              ],
            ),
          ),
        ),
        if (showAiComment) ...[
          const SizedBox(height: AppSpacing.m),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (report.transactionCount == 0)
                    const Text('No hay movimientos este mes')
                  else ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        remainingComments <= 0
                            ? 'Has llegado al máximo de comentarios de esta sesión'
                            : 'Te quedan $remainingComments comentarios',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (comment != null) Text(comment!, style: theme.textTheme.bodyMedium),
                    if (comment != null) const SizedBox(height: AppSpacing.s),
                    if (isGenerating)
                      Row(
                        children: [
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: Text(
                              progressMessage,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      FilledButton.icon(
                        onPressed: remainingComments <= 0 ? null : onGenerateComment,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generar comentario con IA'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Semantics(
        label: text,
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ComparisonBody extends StatelessWidget {
  const _ComparisonBody({required this.comparison});

  final MonthlyComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = this.comparison;
    if (comparison == null) {
      return Text(
        'Sin datos del mes anterior.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return _ComparisonRow(
      label: 'Gasto total',
      deltaCents: comparison.expenseDeltaCents,
      deltaPercent: comparison.expenseDeltaPercent,
    );
  }
}

/// Fila de comparación: flecha + texto (nunca solo color ni solo la
/// flecha) con la diferencia absoluta y, si se puede calcular, el
/// porcentaje.
class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.deltaCents, required this.deltaPercent});

  final String label;
  final int deltaCents;
  final double? deltaPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final isIncrease = deltaCents > 0;
    final isDecrease = deltaCents < 0;
    final color = isIncrease ? finance.expense : (isDecrease ? finance.income : theme.colorScheme.onSurface);
    final icon = isIncrease
        ? Icons.arrow_upward
        : (isDecrease ? Icons.arrow_downward : Icons.remove);
    final percentText = deltaPercent == null ? '' : ' (${formatPercentage(deltaPercent!.abs())})';
    final text = '$label: ${formatCents(deltaCents.abs())} ${isIncrease ? 'más' : (isDecrease ? 'menos' : 'igual')}'
        ' que el mes anterior$percentText';

    return Semantics(
      label: text,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
