import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transactions/load_demo_data.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/parsed_transaction.dart';
import '../../domain/transactions/transaction.dart';
import '../../enable_ai.dart';
import '../auth/auth_providers.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';
import 'day_groups.dart';
import 'formatters.dart';
import 'natural_language_input.dart';
import 'transaction_form_screen.dart';
import 'transaction_providers.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late DateTime _selectedMonth;
  bool _isLoadingDemo = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm([Transaction? transaction]) {
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(userId: widget.userId)),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> _signOut() async {
    try {
      await ref.read(signOutProvider)();
    } catch (error) {
      if (mounted) _showMessage('No se pudo cerrar la sesión: $error');
    }
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
            tooltip: 'Cargar datos de ejemplo',
            onPressed: _isLoadingDemo ? null : _loadDemoData,
            icon: const Icon(Icons.dataset_outlined),
          ),
          if (enableAi)
            IconButton(
              tooltip: 'Chat',
              onPressed: _openChat,
              icon: const Icon(Icons.chat_bubble_outline),
            ),
          IconButton(
            tooltip: 'Perfil',
            onPressed: _openProfile,
            icon: const Icon(Icons.account_circle_outlined),
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
              _MonthNavigator(
                month: _selectedMonth,
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
              ),
              if (enableAi) NaturalLanguageInput(onParsed: _openFormWithDraft),
              transactionsAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      child: Text(
                        'No se pudieron cargar los movimientos: $error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                data: (transactions) => Expanded(
                  child: Column(
                    children: [
                      _SummaryCard(
                        summary: MonthlySummary.fromTransactions(transactions),
                      ),
                      Expanded(
                        child: transactions.isEmpty
                            ? _EmptyMonth(
                                isLoadingDemo: _isLoadingDemo,
                                onLoadDemo: _loadDemoData,
                              )
                            : _TransactionList(
                                transactions: transactions,
                                onEdit: _openForm,
                                onDelete: _confirmAndDelete,
                              ),
                      ),
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

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.s),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mes anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final balanceColor = summary.balanceCents < 0 ? finance.expense : finance.income;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Balance del mes', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatCents(summary.balanceCents),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: balanceColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: 'Ingresos',
                    value: formatCents(summary.incomeCents),
                    color: finance.income,
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: 'Gastos',
                    value: formatCents(-summary.expenseCents),
                    color: finance.expense,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.isLoadingDemo, required this.onLoadDemo});

  final bool isLoadingDemo;
  final VoidCallback onLoadDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              'No hay movimientos este mes',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Añade uno con el botón Nuevo o carga datos de ejemplo para probar la app.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.l),
            FilledButton.tonalIcon(
              onPressed: isLoadingDemo ? null : onLoadDemo,
              icon: const Icon(Icons.dataset_outlined),
              label: const Text('Cargar datos de ejemplo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.transactions,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Transaction> transactions;
  final void Function([Transaction? transaction]) onEdit;
  final void Function(Transaction transaction) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = groupByDay(transactions);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.xs),
            child: Text(
              formatDayHeader(group.day),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final transaction in group.transactions)
            _TransactionTile(
              transaction: transaction,
              onEdit: () => onEdit(transaction),
              onDelete: () => onDelete(transaction),
            ),
        ],
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
  });

  final Transaction transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final category = transaction.categoryId;
    final amountColor = transaction.isExpense ? finance.expense : finance.income;

    return ListTile(
      onTap: onEdit,
      leading: CircleAvatar(
        backgroundColor: category.color.withValues(alpha: 0.15),
        child: Icon(category.icon, color: category.color, size: 20),
      ),
      title: Text(transaction.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(category.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              formatCents(transaction.amountCents),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(color: amountColor),
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
