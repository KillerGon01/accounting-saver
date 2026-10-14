import 'package:accounting_saver/domain/reports/unusual_expenses.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  required int amountCents,
  DateTime? date,
  Category category = Category.ocio,
  String id = 'tx',
  String description = 'movimiento',
}) {
  final effectiveDate = date ?? DateTime(2026, 10, 10);
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: effectiveDate,
    description: description,
    categoryId: category,
    source: TransactionSource.manual,
    createdAt: effectiveDate,
  );
}

/// 4 gastos de `category` en el histórico, con los importes dados (nunca
/// menos de [unusualExpenseMinHistoryCount], para que la categoría tenga
/// muestra suficiente salvo que el propio test pida lo contrario).
List<Transaction> _history(List<int> amountsCentsAbs, {Category category = Category.ocio}) {
  var counter = 0;
  return [
    for (final amount in amountsCentsAbs)
      _tx(
        id: 'hist-${counter++}',
        amountCents: -amount,
        date: DateTime(2026, 9, 1 + counter),
        category: category,
      ),
  ];
}

void main() {
  group('detectUnusualExpenses', () {
    test('detecta un gasto que supera el doble de la mediana de su categoría', () {
      // Mediana del histórico (4 gastos, par): (6.000+6.400)/2 = 6.200.
      final history = _history([5000, 6000, 6400, 7000]);
      final current = [_tx(id: 'actual', amountCents: -13000, category: Category.ocio)];

      final result = detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history);

      expect(result, hasLength(1));
      expect(result.single.amountCentsAbs, 13000);
      expect(result.single.categoryMedianCentsAbs, 6200);
      expect(result.single.categoryHistoryCount, 4);
    });

    test(
      'justo en el límite: el doble exacto de la mediana no es inusual, uno más sí '
      '(mediana par redondeada hacia abajo: (6.000+6.400)/2 = 6.200)',
      () {
        final history = _history([5000, 6000, 6400, 7000]);

        final exactlyDouble = detectUnusualExpenses(
          currentMonthTransactions: [_tx(id: 'limite', amountCents: -12400, category: Category.ocio)],
          historyTransactions: history,
        );
        expect(exactlyDouble, isEmpty);

        final oneCentMore = detectUnusualExpenses(
          currentMonthTransactions: [_tx(id: 'justo-encima', amountCents: -12401, category: Category.ocio)],
          historyTransactions: history,
        );
        expect(oneCentMore, hasLength(1));
      },
    );

    test('una categoría con menos de 4 gastos en el histórico no avisa, aunque el importe sea alto', () {
      final history = _history([1000, 1000, 1000]); // solo 3
      final current = [_tx(id: 'caro', amountCents: -1000000, category: Category.ocio)];

      expect(
        detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history),
        isEmpty,
      );
    });

    test('excluye un gasto que coincide con un recurrente (mismo concepto e importe)', () {
      // "Alquiler" de 85.000 en 2 meses del histórico → recurrente.
      final history = [
        ..._history([1000, 1000, 1000, 1000]), // ocio, para que no sea el histórico vacío
        for (final month in [6, 7, 8, 9])
          _tx(
            id: 'alq-$month',
            amountCents: -85000,
            date: DateTime(2026, month, 1),
            description: 'Alquiler',
            category: Category.hogar,
          ),
      ];
      final current = [
        _tx(id: 'alquiler-mes-actual', amountCents: -85000, description: 'Alquiler', category: Category.hogar),
      ];

      expect(
        detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history),
        isEmpty,
      );
    });

    test('mediana con número impar de datos: el del centro tras ordenar', () {
      // 5 datos (impar): ordenados 1000, 3000, 5000, 9000, 20000 → centro 5000.
      final oddHistory = [
        for (final amount in [1000, 3000, 5000, 9000, 20000])
          _tx(id: 'odd-$amount', amountCents: -amount, date: DateTime(2026, 9, 1)),
      ];
      final current = [_tx(id: 'actual', amountCents: -10001)]; // > 2*5000

      final result = detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: oddHistory);

      expect(result.single.categoryMedianCentsAbs, 5000);
    });

    test('mediana con número par de datos: la media entera de los dos centrales, redondeada hacia abajo', () {
      // Ordenados: 5000, 6000, 6400, 7000 → centrales 6000 y 6400 → (6000+6400)/2 = 6200.
      final history = _history([7000, 5000, 6400, 6000]);
      final current = [_tx(id: 'actual', amountCents: -12401)];

      final result = detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history);

      expect(result.single.categoryMedianCentsAbs, 6200);
    });

    test('mes sin histórico: ninguna categoría tiene muestra, así que no hay ningún aviso', () {
      final current = [_tx(id: 'cualquiera', amountCents: -500000)];

      expect(
        detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: const []),
        isEmpty,
      );
    });

    test('solo mira gastos: un ingreso grande en el histórico o en el mes actual no cuenta', () {
      final history = _history([1000, 1000, 1000, 1000]);
      final current = [_tx(id: 'ingreso', amountCents: 500000, category: Category.ocio)];

      expect(
        detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history),
        isEmpty,
      );
    });

    test('solo compara dentro de la misma categoría: un histórico caro de otra categoría no afecta', () {
      final history = [
        ..._history([100000, 100000, 100000, 100000], category: Category.hogar),
        ..._history([1000, 1000, 1000, 1000], category: Category.ocio),
      ];
      // 2.500 en ocio no es inusual para el histórico de ocio (mediana 1.000,
      // el doble es 2.000, pero sí lo sería si comparase contra hogar).
      final current = [_tx(id: 'ocio-caro', amountCents: -2500, category: Category.ocio)];

      final result = detectUnusualExpenses(currentMonthTransactions: current, historyTransactions: history);

      expect(result, hasLength(1));
      expect(result.single.categoryMedianCentsAbs, 1000);
    });
  });
}
