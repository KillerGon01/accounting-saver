import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/payroll/parse_payroll.dart';
import '../../domain/payroll/payroll_glossary.dart';
import '../../domain/transactions/transaction_source.dart';
import '../help/help_sheet.dart';
import '../help/help_topic.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import '../transactions/transaction_form_screen.dart';
import 'payroll_error_messages.dart';
import 'payroll_file_picker.dart';
import 'payroll_providers.dart';

/// When each progress notice is added while waiting for the reply,
/// same as in `ChatScreen`: just text so the wait doesn't look stuck,
/// unrelated to the request's real timeout.
const _slowReadWarningDelay = Duration(seconds: 10);
const _verySlowReadWarningDelay = Duration(seconds: 45);
const _extremelySlowReadWarningDelay = Duration(seconds: 120);

/// Text for the remaining-readings counter, with correct
/// singular/plural: "Te queda 1 lectura" (exactly one), "Te quedan N
/// lecturas" (more than one), or "No te quedan lecturas" (none).
String remainingReadsLabel(int remaining) {
  if (remaining <= 0) return 'No te quedan lecturas';
  if (remaining == 1) return 'Te queda 1 lectura';
  return 'Te quedan $remaining lecturas';
}

/// Reads a payroll PDF with AI and proposes an income if its figures
/// match. Only available on web (see the button that opens this
/// screen in `TransactionsScreen`). The PDF only lives in the
/// browser's memory for the duration of this screen: it isn't saved
/// anywhere nor logged.
class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  bool _isReading = false;
  bool _isSlowRead = false;
  bool _isVerySlowRead = false;
  bool _isExtremelySlowRead = false;
  Timer? _slowReadTimer;
  Timer? _verySlowReadTimer;
  Timer? _extremelySlowReadTimer;
  int? _remainingReads;
  ParsePayrollResult? _result;

  @override
  void initState() {
    super.initState();
    _remainingReads = ref.read(parsePayrollProvider(widget.userId)).remainingReads;
  }

  @override
  void dispose() {
    _slowReadTimer?.cancel();
    _verySlowReadTimer?.cancel();
    _extremelySlowReadTimer?.cancel();
    super.dispose();
  }

  Future<bool> _confirmFictitiousOnly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solo documentos ficticios'),
        content: const Text(
          'Solo documentos ficticios. El nivel gratuito de Gemini permite a '
          'Google usar el contenido para mejorar sus productos; no subas '
          'una nómina real.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entendido, continuar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _pickAndRead() async {
    final confirmed = await _confirmFictitiousOnly();
    if (!confirmed || !mounted) return;

    final bytes = await pickPayrollPdfBytes();
    if (bytes == null || !mounted) return;

    setState(() {
      _isReading = true;
      _isSlowRead = false;
      _isVerySlowRead = false;
      _isExtremelySlowRead = false;
      _result = null;
    });

    _slowReadTimer = Timer(_slowReadWarningDelay, () {
      if (!mounted || !_isReading) return;
      setState(() => _isSlowRead = true);
    });
    _verySlowReadTimer = Timer(_verySlowReadWarningDelay, () {
      if (!mounted || !_isReading) return;
      setState(() => _isVerySlowRead = true);
    });
    _extremelySlowReadTimer = Timer(_extremelySlowReadWarningDelay, () {
      if (!mounted || !_isReading) return;
      setState(() => _isExtremelySlowRead = true);
    });

    try {
      final result = await ref.read(parsePayrollProvider(widget.userId))(bytes);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payrollErrorMessage(error))),
      );
    } finally {
      _slowReadTimer?.cancel();
      _verySlowReadTimer?.cancel();
      _extremelySlowReadTimer?.cancel();
      final remaining = ref.read(parsePayrollProvider(widget.userId)).remainingReads;
      if (mounted) {
        setState(() {
          _isReading = false;
          _remainingReads = remaining;
        });
      }
    }
  }

  Future<void> _openFormWithProposal() async {
    final proposal = _result?.proposedTransaction;
    if (proposal == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(
          userId: widget.userId,
          initialDraft: proposal,
          initialSource: TransactionSource.payroll,
        ),
      ),
    );
  }

  String get _progressMessage {
    final parts = ['Leyendo la nómina...'];
    if (_isSlowRead) parts.add('Esto está tardando más de lo normal...');
    if (_isVerySlowRead) parts.add('Puede tardar hasta un par de minutos.');
    if (_isExtremelySlowRead) {
      parts.add('Sigue en marcha: hoy el servicio está lento y puede tardar hasta unos 3 minutos.');
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remainingReads ?? ParsePayroll.maxReadsPerSession;
    final limitReached = remaining <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leer nómina'),
        actions: const [HelpButton(topic: HelpTopic.payroll)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    remainingReadsLabel(remaining),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                FilledButton.icon(
                  onPressed: (_isReading || limitReached) ? null : _pickAndRead,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Elegir PDF de nómina'),
                ),
                if (_isReading) ...[
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          _progressMessage,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: AppSpacing.l),
                  PayrollResultView(
                    result: _result!,
                    onAddIncome: _openFormWithProposal,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PayrollResultView extends StatelessWidget {
  const PayrollResultView({super.key, required this.result, required this.onAddIncome});

  final ParsePayrollResult result;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extraction = result.extraction;
    final matches = result.validation.matches;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatDate(extraction.periodStart)} – ${formatDate(extraction.periodEnd)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s),
            _AmountRow(label: 'Bruto', cents: extraction.grossCents),
            _AmountRow(label: 'Líquido', cents: extraction.netAsStatedCents),
            const SizedBox(height: AppSpacing.m),
            Text('Deducciones', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            for (final deduction in result.validation.deductionBreakdown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${deduction.concept}: ${formatCents(deduction.cents)} '
                      '(${deduction.percentOfGross.toStringAsFixed(1)} % del bruto)',
                    ),
                    Text(
                      payrollGlossaryDescription(deduction.concept),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Text(
              payrollGlossaryDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              Text('Avisos', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              for (final warning in result.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(child: Text(warning)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.m),
            if (matches)
              FilledButton.icon(
                onPressed: onAddIncome,
                icon: const Icon(Icons.add),
                label: const Text('Añadir como ingreso'),
              )
            else
              Text(
                'No se propone ningún ingreso: las cifras del documento no cuadran.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.cents});

  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(formatCents(cents), style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
