import '../../domain/transactions/transaction.dart';

class DayGroup {
  DayGroup({required this.day, required this.transactions});

  final DateTime day;
  final List<Transaction> transactions;
}

/// Agrupa movimientos por día conservando el orden de la lista de entrada.
List<DayGroup> groupByDay(List<Transaction> transactions) {
  final groups = <DayGroup>[];
  for (final transaction in transactions) {
    final day = DateTime(transaction.date.year, transaction.date.month, transaction.date.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.transactions.add(transaction);
    } else {
      groups.add(DayGroup(day: day, transactions: [transaction]));
    }
  }
  return groups;
}
