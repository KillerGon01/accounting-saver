import 'package:flutter/material.dart';

import '../../../domain/transactions/transaction.dart';
import '../../common/staggered_entrance.dart';
import '../../theme/app_theme.dart';
import '../category_style.dart';
import '../day_groups.dart';
import '../formatters.dart';

class TransactionList extends StatelessWidget {
  const TransactionList({
    super.key,
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
    var index = 0;

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
            StaggeredEntrance(
              index: index++,
              child: _TransactionTile(
                transaction: transaction,
                onEdit: () => onEdit(transaction),
                onDelete: () => onDelete(transaction),
              ),
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
