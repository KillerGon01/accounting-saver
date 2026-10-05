import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transactions/load_demo_data.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/transaction.dart';
import '../auth/auth_providers.dart';
import 'formatters.dart';
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
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
              transactionsAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                      _SummaryHeader(
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                label: 'Ingresos',
                value: formatCents(summary.incomeCents),
                color: Colors.green.shade700,
              ),
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Gastos',
                value: formatCents(-summary.expenseCents),
                color: colors.error,
              ),
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Balance',
                value: formatCents(summary.balanceCents),
                color: colors.onSurface,
              ),
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
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No hay movimientos este mes', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
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
    final colors = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: transactions.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        final amountColor = transaction.isExpense ? colors.error : Colors.green.shade700;
        return ListTile(
          onTap: () => onEdit(transaction),
          title: Text(transaction.description),
          subtitle: Text(
            '${formatDate(transaction.date)} · ${transaction.categoryId.label}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatCents(transaction.amountCents),
                style: TextStyle(color: amountColor, fontWeight: FontWeight.w600),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => onDelete(transaction),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}
