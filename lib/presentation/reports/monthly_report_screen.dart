import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_check_config.dart';
import '../../domain/reports/month_end_forecast.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/unusual_expenses.dart';
import '../common/animated_balance_text.dart';
import '../common/firestore_error_messages.dart';
import '../common/staggered_entrance.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import '../transactions/transaction_providers.dart';
import 'category_bar_chart.dart';
import 'report_error_messages.dart';
import 'report_formatters.dart';
import 'report_providers.dart';

const _slowReplyWarningDelay = Duration(seconds: 10);
const _verySlowReplyWarningDelay = Duration(seconds: 45);
const _extremelySlowReplyWarningDelay = Duration(seconds: 120);

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
  Timer? _extremelySlowReplyTimer;
  bool _isSlowReply = false;
  bool _isVerySlowReply = false;
  bool _isExtremelySlowReply = false;

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
    _extremelySlowReplyTimer?.cancel();
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
      _isExtremelySlowReply = false;
    });
  }

  Future<void> _generateComment(MonthlyReport report) async {
    setState(() {
      _isGenerating = true;
      _isSlowReply = false;
      _isVerySlowReply = false;
      _isExtremelySlowReply = false;
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
    _extremelySlowReplyTimer = Timer(_extremelySlowReplyWarningDelay, () {
      if (!mounted || !_isGenerating) return;
      setState(() => _isExtremelySlowReply = true);
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
      _extremelySlowReplyTimer?.cancel();
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
    if (_isExtremelySlowReply) {
      parts.add('Sigue en marcha: hoy el servicio está lento y puede tardar hasta unos 3 minutos.');
    }
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
    // `.value` (nullable, no lanza), nunca `.when`/`.requireValue`: si
    // falla el cálculo de la previsión (las consultas extra de los 3
    // meses anteriores), el resto del resumen mensual sigue funcionando
    // con normalidad y la tarjeta de previsión simplemente no aparece
    // (ver docs/design.md, "Riesgos").
    final forecast = ref.watch(monthEndForecastProvider(params)).value;
    // Mismo motivo que `forecast`: si falla el cálculo (ver
    // docs/design.md, "Riesgos"), el resto del resumen sigue funcionando
    // y la tarjeta de gastos inusuales simplemente no aparece.
    final unusualExpenses = ref.watch(unusualExpensesProvider(params)).value;

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
                    forecast: forecast,
                    unusualExpenses: unusualExpenses,
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
    required this.forecast,
    required this.unusualExpenses,
    required this.showAiComment,
    required this.comment,
    required this.isGenerating,
    required this.progressMessage,
    required this.remainingComments,
    required this.onGenerateComment,
  });

  final MonthlyReport report;

  /// `null` si el mes mostrado no es el mes en curso, o si falló el
  /// cálculo (ver `MonthlyReportScreen.build`): en los dos casos, sin
  /// tarjeta de previsión.
  final MonthEndForecast? forecast;

  /// `null` si el mes mostrado no es el mes en curso, o si falló el
  /// cálculo: en los dos casos, sin tarjeta de gastos inusuales.
  final UnusualExpensesResult? unusualExpenses;
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
        StaggeredEntrance(
          index: 0,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Balance del mes', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  AnimatedBalanceText(
                    cents: report.balanceCents,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
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
                          // Con signo, igual que en la pantalla de movimientos
                          // (`_SummaryCard`/`_SummaryItem`) y que cada
                          // movimiento individual (`_TransactionTile`):
                          // `report.expenseCents` es una magnitud positiva en
                          // dominio (ver `MonthlySummary`/`MonthlyReport`), y
                          // aquí solo se decide cómo mostrarla.
                          label: 'Gastos',
                          value: formatCents(-report.expenseCents),
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
        ),
        const SizedBox(height: AppSpacing.m),
        StaggeredEntrance(
          index: 1,
          child: Card(
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
        ),
        const SizedBox(height: AppSpacing.m),
        StaggeredEntrance(
          index: 2,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      Text('Comparación con el mes anterior', style: theme.textTheme.labelLarge),
                      if (report.isCurrentMonth && report.comparison != null)
                        Text(
                          '(parcial, mes en curso)',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s),
                  _ComparisonBody(comparison: report.comparison),
                ],
              ),
            ),
          ),
        ),
        if (showAiComment) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(
            index: 3,
            child: Card(
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
          ),
        ],
        if (forecast != null) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(index: 4, child: _MonthEndForecastCard(forecast: forecast!)),
        ],
        if (unusualExpenses != null) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(index: 5, child: _UnusualExpensesCard(result: unusualExpenses!)),
        ],
      ],
    );
  }
}

/// Tarjeta "Previsión de fin de mes": gasto acumulado hasta hoy, cada
/// recurrente pendiente con su importe y día, el gasto previsto (suma de
/// los dos) y el balance previsto. Solo se muestra cuando
/// `MonthlyReportScreen` recibe un [forecast] no nulo (mes en curso, y el
/// cálculo no ha fallado — ver `report_providers.dart`).
class _MonthEndForecastCard extends StatelessWidget {
  const _MonthEndForecastCard({required this.forecast});

  final MonthEndForecast forecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Previsión de fin de mes (estimación)', style: theme.textTheme.labelLarge),
            if (forecast.truncated) ...[
              const SizedBox(height: AppSpacing.xs),
              _InfoBanner(
                icon: Icons.warning_amber_outlined,
                text: 'Previsión parcial: se han leído los primeros 2.000 movimientos de alguno de los meses analizados.',
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            _ForecastLine(
              label: 'Gastado hasta hoy',
              value: formatCents(forecast.accumulatedExpenseCents),
            ),
            if (forecast.pendingRecurringExpenses.isEmpty)
              _ForecastLine(label: 'Recurrentes pendientes este mes', value: 'ninguno', indent: true)
            else
              for (final pending in forecast.pendingRecurringExpenses)
                _ForecastLine(
                  label: '${_capitalize(pending.description)} (día ${pending.usualDay})',
                  value: formatCents(pending.amountCentsAbs),
                  indent: true,
                ),
            const Divider(height: AppSpacing.m),
            _ForecastLine(
              label: 'Gasto previsto',
              value: formatCents(forecast.forecastExpenseCents),
              emphasize: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _ForecastLine(
              label: 'Balance previsto',
              value: formatCents(forecast.forecastBalanceCents),
              emphasize: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Los ingresos que aún no hayan entrado no se incluyen.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ingresos registrados: ${formatCents(forecast.registeredIncomeCents)}.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (forecast.overdueUnregisteredExpenses.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                'Esperados y no registrados todavía (no incluidos en la previsión):',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              for (final overdue in forecast.overdueUnregisteredExpenses)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s, top: 2),
                  child: Text(
                    '${_capitalize(overdue.description)} (día ${overdue.usualDay}): '
                    '${formatCents(overdue.amountCentsAbs)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.s),
            Text(
              'Estimación basada solo en gastos recurrentes detectados en meses '
              'anteriores: no prevé ingresos futuros ni gasto variable.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

/// Tarjeta "Gastos inusuales": gastos del mes en curso cuyo importe
/// destaca frente al histórico de su propia categoría (ver
/// `detectUnusualExpenses`, docs/design.md "Detección de gastos
/// inusuales"). Solo se muestra cuando `MonthlyReportScreen` recibe un
/// [result] no nulo (mes en curso, y el cálculo no ha fallado — ver
/// `report_providers.dart`).
class _UnusualExpensesCard extends StatelessWidget {
  const _UnusualExpensesCard({required this.result});

  final UnusualExpensesResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gastos inusuales (estimación)', style: theme.textTheme.labelLarge),
            if (result.truncated) ...[
              const SizedBox(height: AppSpacing.xs),
              const _InfoBanner(
                icon: Icons.warning_amber_outlined,
                text: 'Análisis parcial: se han leído los primeros 2.000 movimientos de alguno de '
                    'los meses analizados.',
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            if (result.expenses.isEmpty)
              Text(
                'No se han detectado gastos inusuales. Se compara cada gasto de este mes con la '
                'mediana de su categoría en los 3 meses anteriores; necesita al menos '
                '$unusualExpenseMinHistoryCount gastos de esa categoría en ese histórico para '
                'poder comparar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final expense in result.expenses) _UnusualExpenseTile(expense: expense),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Estimación estadística, no una alerta de fraude: puede equivocarse, sobre todo con '
              'poco histórico.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila de `_UnusualExpensesCard`: el icono y el color del importe son
/// un apoyo visual, nunca la única pista — el texto ya dice "inusual" de
/// forma explícita a través de `Semantics.label`, y la comparación con la
/// mediana va siempre en una segunda línea de texto, no solo en el color.
class _UnusualExpenseTile extends StatelessWidget {
  const _UnusualExpenseTile({required this.expense});

  final UnusualExpense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = formatCents(-expense.amountCentsAbs);
    final detailText =
        '${formatDate(expense.date)} — mediana de ${expense.categoryId.label}: '
        '${formatCents(expense.categoryMedianCentsAbs)} (${expense.categoryHistoryCount} gastos '
        'analizados)';
    final semanticsLabel =
        'Gasto inusual: ${_capitalize(expense.description)}, $amountText, $detailText';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Semantics(
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.trending_up, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_capitalize(expense.description)} · ${expense.categoryId.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      detailText,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Text(
                amountText,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

/// Una fila "etiqueta: importe" de la tarjeta de previsión. [indent]
/// marca una línea del desglose (un recurrente pendiente) con una
/// sangría, para distinguirla visualmente de los totales sin depender
/// solo de un color.
class _ForecastLine extends StatelessWidget {
  const _ForecastLine({
    required this.label,
    required this.value,
    this.indent = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool indent;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleSmall
        : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: EdgeInsets.only(left: indent ? AppSpacing.m : 0, top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
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
