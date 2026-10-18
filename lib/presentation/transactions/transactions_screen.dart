import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transactions/load_demo_data.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/parsed_transaction.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_filter.dart';
import '../../app_check_config.dart';
import '../auth/auth_providers.dart';
import '../chat/chat_screen.dart';
import '../common/firestore_error_messages.dart';
import '../help/help_sheet.dart';
import '../help/help_topic.dart';
import '../payroll/payroll_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/monthly_report_screen.dart';
import '../savings/savings_goals_screen.dart';
import '../theme/app_theme.dart';
import 'natural_language_input.dart';
import 'transaction_filter_sheet.dart';
import 'transaction_form_screen.dart';
import 'transaction_providers.dart';
import 'widgets/empty_states.dart';
import 'widgets/filter_status_bar.dart';
import 'widgets/month_navigator.dart';
import 'widgets/summary_card.dart';
import 'widgets/transaction_list.dart';

/// The `AppBar`'s "Más opciones" menu entries (see
/// `_TransactionsScreenState._handleMoreMenuSelection`): a single
/// icon instead of one per destination, so as not to add a seventh
/// icon to the bar (see docs/design.md, "Metas de ahorro").
enum _MoreMenuEntry { help, profile, savingsGoals }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late DateTime _selectedMonth;
  bool _isLoadingDemo = false;

  /// Search and filters over the month's already-loaded list (never
  /// a new query to Firestore, see `TransactionFilter`). Lives in the
  /// screen's state, without persisting: resets when changing month
  /// (`_changeMonth`) and, when switching user, because `AuthGate`
  /// unmounts this entire screen (a new instance of this state is
  /// always born with an empty filter).
  TransactionFilter _filter = TransactionFilter();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
      _filter = TransactionFilter();
    });
  }

  void _clearFilters() => setState(() => _filter = TransactionFilter());

  Future<void> _openFilterSheet() async {
    final result = await showTransactionFilterSheet(context, current: _filter);
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Hides the current notice before navigating to another screen
  /// (see docs/design.md, "Aviso estable al navegar"): a floating
  /// `SnackBar` is positioned above the `FloatingActionButton` when
  /// there is one, so if it's still visible when entering a screen
  /// without a FAB, the `Scaffold` recomputes its vertical position
  /// and gives the impression that it "rises" or changes size
  /// mid-transition.
  void _hideSnackBar() => ScaffoldMessenger.of(context).hideCurrentSnackBar();

  Future<void> _openForm([Transaction? transaction]) {
    _hideSnackBar();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(
          userId: widget.userId,
          transaction: transaction,
        ),
      ),
    );
  }

  Future<void> _openFormWithDraft(ParsedTransaction draft) {
    _hideSnackBar();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(
          userId: widget.userId,
          initialDraft: draft,
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text('¿Seguro que quieres eliminar "${transaction.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(deleteTransactionProvider)(
        userId: widget.userId,
        transactionId: transaction.id,
      );
    } catch (error) {
      if (mounted) _showMessage('No se pudo eliminar el movimiento: $error');
    }
  }

  Future<void> _loadDemoData() async {
    setState(() => _isLoadingDemo = true);
    try {
      final result = await ref.read(loadDemoDataProvider)(
        userId: widget.userId,
        now: DateTime.now(),
      );
      if (!mounted) return;
      _showMessage(switch (result) {
        DemoDataResult.loaded => 'Datos de ejemplo cargados',
        DemoDataResult.alreadyLoaded => 'Ya hay datos de ejemplo cargados',
      });
    } catch (error) {
      if (mounted) _showMessage('No se pudieron cargar los datos de ejemplo: $error');
    } finally {
      if (mounted) setState(() => _isLoadingDemo = false);
    }
  }

  void _openChat() {
    _hideSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(userId: widget.userId)),
    );
  }

  void _openPayroll() {
    _hideSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PayrollScreen(userId: widget.userId)),
    );
  }

  void _openMonthlyReport() {
    _hideSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MonthlyReportScreen(userId: widget.userId)),
    );
  }

  void _openProfile() {
    _hideSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _openSavingsGoals() {
    _hideSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SavingsGoalsScreen(userId: widget.userId)),
    );
  }

  void _handleMoreMenuSelection(_MoreMenuEntry entry) {
    switch (entry) {
      case _MoreMenuEntry.help:
        showHelpSheet(context, HelpTopic.transactions);
      case _MoreMenuEntry.profile:
        _openProfile();
      case _MoreMenuEntry.savingsGoals:
        _openSavingsGoals();
    }
  }

  Future<void> _signOut() async {
    try {
      // The only function shared by the app's three sign-out buttons
      // (see docs/design.md, "Avisos de sesión"): leaves `signedOut`
      // in `sessionFeedbackProvider` only if sign-out finishes
      // successfully.
      await ref.read(signOutWithFeedbackProvider)();
    } catch (error) {
      if (mounted) _showMessage('No se pudo cerrar la sesión: $error');
    }
  }

  /// The summary (`SummaryCard`) always keeps seeing unfiltered
  /// [transactions] (the summary is for the whole month); only the
  /// list below uses the filtered version, computed right here with
  /// `filterTransactions` (no new query, it only trims in memory the
  /// month's list that had already been requested from Firestore).
  Widget _buildMonthBody(List<Transaction> transactions) {
    final filtered = filterTransactions(transactions, _filter);

    return Expanded(
      child: Column(
        children: [
          SummaryCard(
            summary: MonthlySummary.fromTransactions(transactions),
          ),
          if (_filter.isActive)
            FilterStatusBar(
              matchCount: filtered.length,
              totalCount: transactions.length,
              onClear: _clearFilters,
            ),
          Expanded(
            child: transactions.isEmpty
                ? EmptyMonth(
                    isLoadingDemo: _isLoadingDemo,
                    onLoadDemo: _loadDemoData,
                  )
                : filtered.isEmpty
                    ? FilteredEmptyState(onClearFilters: _clearFilters)
                    : TransactionList(
                        transactions: filtered,
                        onEdit: _openForm,
                        onDelete: _confirmAndDelete,
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = MonthlyTransactionsParams(
      userId: widget.userId,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
    );
    final transactionsAsync = ref.watch(monthlyTransactionsStreamProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        actions: [
          IconButton(
            tooltip: _filter.isActive ? 'Buscar y filtrar (filtros activos)' : 'Buscar y filtrar',
            onPressed: _openFilterSheet,
            icon: _filter.isActive
                ? Badge(
                    label: Text('${_filter.activeCriteriaCount}'),
                    child: const Icon(Icons.filter_alt),
                  )
                : const Icon(Icons.filter_alt_outlined),
          ),
          IconButton(
            tooltip: 'Cargar datos de ejemplo',
            onPressed: _isLoadingDemo ? null : _loadDemoData,
            icon: const Icon(Icons.dataset_outlined),
          ),
          IconButton(
            tooltip: 'Resumen del mes',
            onPressed: _openMonthlyReport,
            icon: const Icon(Icons.insights_outlined),
          ),
          if (effectiveEnableAi)
            IconButton(
              tooltip: 'Chat',
              onPressed: _openChat,
              icon: const Icon(Icons.chat_bubble_outline),
            ),
          if (effectiveEnableAi && kIsWeb)
            IconButton(
              tooltip: 'Leer nómina',
              onPressed: _openPayroll,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          PopupMenuButton<_MoreMenuEntry>(
            tooltip: 'Más opciones',
            onSelected: _handleMoreMenuSelection,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MoreMenuEntry.help,
                child: ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('Ayuda'),
                ),
              ),
              PopupMenuItem(
                value: _MoreMenuEntry.profile,
                child: ListTile(
                  leading: Icon(Icons.account_circle_outlined),
                  title: Text('Perfil'),
                ),
              ),
              PopupMenuItem(
                value: _MoreMenuEntry.savingsGoals,
                child: ListTile(
                  leading: Icon(Icons.savings_outlined),
                  title: Text('Metas de ahorro'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Añadir un movimiento',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              MonthNavigator(
                month: _selectedMonth,
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
              ),
              if (effectiveEnableAi) NaturalLanguageInput(onParsed: _openFormWithDraft),
              transactionsAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      child: Text(
                        firestoreErrorMessage(
                          error,
                          fallback: 'No se pudieron cargar los movimientos. Inténtalo de nuevo más tarde.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                data: _buildMonthBody,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
