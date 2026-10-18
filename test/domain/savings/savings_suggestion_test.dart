import 'package:accounting_saver/domain/savings/savings_suggestion.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var counter = 0;

  Transaction tx({
    required int amountCents,
    required DateTime date,
    Category category = Category.otros,
    String description = 'movimiento',
  }) {
    counter++;
    return Transaction(
      id: 'tx-$counter',
      amountCents: amountCents,
      date: date,
      description: description,
      categoryId: category,
      source: TransactionSource.manual,
      createdAt: date,
    );
  }

  group('calculateSavingsSuggestions', () {
    test('un recurrente aparece como opción, con su importe mensual completo', () {
      final history = [
        tx(amountCents: -1500, date: DateTime(2026, 7, 5), description: 'Netflix', category: Category.suscripciones),
        tx(amountCents: -1500, date: DateTime(2026, 8, 5), description: 'Netflix', category: Category.suscripciones),
        tx(amountCents: -1500, date: DateTime(2026, 9, 5), description: 'Netflix', category: Category.suscripciones),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

      expect(result.suggestions, hasLength(1));
      final suggestion = result.suggestions.single;
      expect(suggestion.type, SavingsSuggestionType.recurring);
      expect(suggestion.description, 'netflix');
      expect(suggestion.amountCents, 1500);
      expect(suggestion.categoryId, Category.suscripciones);
      expect(result.monthlyCoveredCents, 1500);
    });

    test('el recorte del 20% de una categoría no cuenta el gasto ya contado como recurrente', () {
      final history = [
        // Recurring: must not enter the cut's average.
        tx(amountCents: -2000, date: DateTime(2026, 7, 1), description: 'Spotify', category: Category.ocio),
        tx(amountCents: -2000, date: DateTime(2026, 8, 1), description: 'Spotify', category: Category.ocio),
        tx(amountCents: -2000, date: DateTime(2026, 9, 1), description: 'Spotify', category: Category.ocio),
        // Not recurring, one per month, 3,000 in total -> average 1,000 -> 20% cut = 200.
        tx(amountCents: -1000, date: DateTime(2026, 7, 15), description: 'Cine', category: Category.ocio),
        tx(amountCents: -1000, date: DateTime(2026, 8, 20), description: 'Bolera', category: Category.ocio),
        tx(amountCents: -1000, date: DateTime(2026, 9, 10), description: 'Escape room', category: Category.ocio),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

      final cut = result.suggestions.firstWhere((s) => s.type == SavingsSuggestionType.categoryCut);
      expect(cut.categoryId, Category.ocio);
      expect(cut.amountCents, 200);

      final recurring = result.suggestions.firstWhere((s) => s.type == SavingsSuggestionType.recurring);
      expect(recurring.amountCents, 2000);

      expect(result.monthlyCoveredCents, 2000 + 200);
    });

    test(
      'un recurrente en Hogar no aparece (categoría excluida); uno en Suscripciones sí',
      () {
        final history = [
          tx(amountCents: -85000, date: DateTime(2026, 7, 1), description: 'Alquiler', category: Category.hogar),
          tx(amountCents: -85000, date: DateTime(2026, 8, 1), description: 'Alquiler', category: Category.hogar),
          tx(amountCents: -1500, date: DateTime(2026, 7, 5), description: 'Netflix', category: Category.suscripciones),
          tx(amountCents: -1500, date: DateTime(2026, 8, 5), description: 'Netflix', category: Category.suscripciones),
        ];

        final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

        expect(result.suggestions, hasLength(1));
        expect(result.suggestions.single.description, 'netflix');
        expect(result.monthlyCoveredCents, 1500);
      },
    );

    test('gasto inusual del mes en curso aparte: el importe es el exceso sobre la mediana, no el gasto completo', () {
      // Transporte category (not in savingsSuggestionCutCategories,
      // not excluded): this way it doesn't mix with a percentage
      // cut (b) and the monthly coverage can only come from (a)/(b),
      // never from (c).
      final history = [
        tx(amountCents: -800, date: DateTime(2026, 7, 10), category: Category.transporte),
        tx(amountCents: -900, date: DateTime(2026, 8, 10), category: Category.transporte),
        tx(amountCents: -1100, date: DateTime(2026, 9, 10), category: Category.transporte),
        tx(amountCents: -1200, date: DateTime(2026, 9, 20), category: Category.transporte),
      ];
      final current = [
        tx(amountCents: -5000, date: DateTime(2026, 10, 5), description: 'Concierto', category: Category.transporte),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: current);

      final excess = result.suggestions.firstWhere((s) => s.type == SavingsSuggestionType.oneOffExcess);
      expect(excess.description, 'Concierto');
      // History's median: 1,000. Excess: 5,000 - 1,000 = 4,000.
      expect(excess.amountCents, 4000);
      // Doesn't add to the monthly coverage.
      expect(result.monthlyCoveredCents, 0);
    });

    test('un gasto inusual en una categoría excluida no genera sugerencia', () {
      final history = [
        tx(amountCents: -800, date: DateTime(2026, 7, 10), category: Category.salud),
        tx(amountCents: -900, date: DateTime(2026, 8, 10), category: Category.salud),
        tx(amountCents: -1100, date: DateTime(2026, 9, 10), category: Category.salud),
        tx(amountCents: -1200, date: DateTime(2026, 9, 20), category: Category.salud),
      ];
      final current = [tx(amountCents: -5000, date: DateTime(2026, 10, 5), category: Category.salud)];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: current);

      expect(result.suggestions, isEmpty);
    });

    test('sin histórico: sin sugerencias, sin lanzar ningún error', () {
      final result = calculateSavingsSuggestions(historyTransactions: const [], currentMonthTransactions: const []);

      expect(result.suggestions, isEmpty);
      expect(result.monthlyCoveredCents, 0);
      expect(result.truncated, isFalse);
    });

    test('redondeo en el borde: 99 céntimos de media mensual da un recorte de 19, no 20', () {
      final history = [
        tx(amountCents: -99, date: DateTime(2026, 7, 1), category: Category.restaurantes),
        tx(amountCents: -99, date: DateTime(2026, 8, 1), category: Category.restaurantes, description: 'otro'),
        tx(amountCents: -99, date: DateTime(2026, 9, 1), category: Category.restaurantes, description: 'otro2'),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

      final cut = result.suggestions.single;
      expect(cut.type, SavingsSuggestionType.categoryCut);
      // Average: 297 ~/ 3 = 99. Cut: 99 * 20 ~/ 100 = 19 (not 19.8 rounded to 20).
      expect(cut.amountCents, 19);
    });

    test('un recorte que redondea a 0 no genera sugerencia', () {
      final history = [
        tx(amountCents: -6, date: DateTime(2026, 7, 1), category: Category.restaurantes),
        tx(amountCents: -6, date: DateTime(2026, 8, 1), category: Category.restaurantes, description: 'otro'),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

      expect(result.suggestions, isEmpty);
    });

    test('resultado ordenado de mayor a menor importe, mezclando tipos', () {
      final history = [
        tx(amountCents: -500, date: DateTime(2026, 7, 1), description: 'Netflix', category: Category.suscripciones),
        tx(amountCents: -500, date: DateTime(2026, 8, 1), description: 'Netflix', category: Category.suscripciones),
        tx(amountCents: -5000, date: DateTime(2026, 7, 1), description: 'Gimnasio', category: Category.otros),
        tx(amountCents: -5000, date: DateTime(2026, 8, 1), description: 'Gimnasio', category: Category.otros),
      ];

      final result = calculateSavingsSuggestions(historyTransactions: history, currentMonthTransactions: const []);

      final amounts = result.suggestions.map((s) => s.amountCents).toList();
      expect(amounts, [5000, 500]);
    });
  });
}
