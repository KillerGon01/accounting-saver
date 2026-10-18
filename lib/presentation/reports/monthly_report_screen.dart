import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_check_config.dart';
import '../../domain/reports/monthly_report.dart';
import '../common/firestore_error_messages.dart';
import '../help/help_sheet.dart';
import '../help/help_topic.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import '../transactions/transaction_providers.dart';
import 'report_error_messages.dart';
import 'report_providers.dart';
import 'widgets/report_body.dart';

const _slowReplyWarningDelay = Duration(seconds: 10);
const _verySlowReplyWarningDelay = Duration(seconds: 45);
const _extremelySlowReplyWarningDelay = Duration(seconds: 120);

/// Monthly report screen: totals, expense by category, comparison
/// with the previous month and, if [showAiComment] allows it, an AI
/// comment on those same figures.
///
/// [showAiComment] is optional and defaults to [effectiveEnableAi]
/// (the same thing that already decides whether the chat or natural
/// language input are shown): it only exists as a parameter so tests
/// can test the screen with and without the AI section without
/// depending on which `--dart-define=ENABLE_AI` `flutter test` was
/// launched with.
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

    // Timers, not an awaited `Future.delayed`: they block nothing
    // (same pattern as `ChatScreen`).
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
    // `.value` (nullable, doesn't throw), never `.when`/`.requireValue`:
    // if the forecast calculation fails (the extra queries over the
    // previous 3 months), the rest of the monthly report keeps
    // working normally and the forecast card simply doesn't appear
    // (see docs/design.md, "Riesgos").
    final forecast = ref.watch(monthEndForecastProvider(params)).value;
    // Same reason as `forecast`: if the calculation fails (see
    // docs/design.md, "Riesgos"), the rest of the report keeps
    // working and the unusual expenses card simply doesn't appear.
    final unusualExpenses = ref.watch(unusualExpensesProvider(params)).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen del mes'),
        actions: const [HelpButton(topic: HelpTopic.monthlyReport)],
      ),
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
                  data: (report) => ReportBody(
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
