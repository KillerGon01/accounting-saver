import 'package:accounting_saver/application/savings/build_savings_suggestions.dart';
import 'package:accounting_saver/application/savings/explain_savings_suggestions.dart';
import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal_progress.dart';
import 'package:accounting_saver/domain/savings/savings_suggestions_summary.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/savings/savings_goal_providers.dart';
import 'package:accounting_saver/presentation/savings/savings_suggestions_sheet.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_savings_suggestions_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';
var _txCounter = 0;

Transaction _tx({
  required int amountCents,
  required DateTime date,
  Category category = Category.suscripciones,
  String description = 'Netflix',
}) {
  _txCounter++;
  return Transaction(
    id: 'tx-$_txCounter',
    amountCents: amountCents,
    date: date,
    description: description,
    categoryId: category,
    source: TransactionSource.manual,
    createdAt: date,
  );
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  String userId = _userId,
  required SavingsGoal goal,
  required SavingsGoalProgress progress,
  bool? showAiButton,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SavingsSuggestionsSheet.show(
                context,
                userId: userId,
                goal: goal,
                progress: progress,
                showAiButton: showAiButton,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Mutable: [_openMultiple]'s "open" button reads its fields at the
/// moment it's pressed, not when it's built, so the sheet can be
/// reopened for another user/goal on the same widget tree without
/// `pumpWidget`-ing a new one (necessary because a
/// `showModalBottomSheet` is still part of the current route: it has
/// to be closed by tapping outside before it can be reopened).
class _OpenParams {
  _OpenParams({required this.userId, required this.goal, required this.progress, this.showAiButton});

  String userId;
  SavingsGoal goal;
  SavingsGoalProgress progress;
  bool? showAiButton;
}

Future<void> _pumpMultiOpenApp(WidgetTester tester, ProviderContainer container, _OpenParams params) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SavingsSuggestionsSheet.show(
                context,
                userId: params.userId,
                goal: params.goal,
                progress: params.progress,
                showAiButton: params.showAiButton,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Closes the currently open sheet (taps outside, in the darkened area)
/// and opens another one for the parameters already updated in
/// [params], on the same widget tree (see [_OpenParams]).
Future<void> _reopen(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('SavingsSuggestionsSheet', () {
    final goal = SavingsGoal(
      id: 'g1',
      name: 'Vacaciones',
      targetCents: 100000,
      savedCents: 0,
      deadline: DateTime(2026, 2, 1),
      createdAt: DateTime(2026, 1, 1),
    );

    testWidgets('muestra el aviso fijo, sin lenguaje de consejo', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          _tx(amountCents: -1500, date: DateTime(2025, 10, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 11, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 12, 5)),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
          ),
        ],
      );
      addTearDown(container.dispose);
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

      await _open(tester, container, goal: goal, progress: progress);

      expect(
        find.textContaining('Opciones informativas calculadas con tus gastos de los últimos 3 meses'),
        findsOneWidget,
      );
      expect(find.textContaining('Decidir qué recortar es cosa tuya'), findsOneWidget);
      expect(find.textContaining('deberías'), findsNothing);
      expect(find.textContaining('te recomendamos'), findsNothing);
    });

    testWidgets(
      'un recurrente se muestra con la primera letra en mayúscula, sin tocar el dato normalizado',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          // Different capitalization between occurrences: all that
          // matters is that the normalized concept (lowercase,
          // collapsed spaces) matches for it to be detected as recurring.
          transactions: [
            _tx(amountCents: -1500, date: DateTime(2025, 10, 5), description: 'NETFLIX PREMIUM'),
            _tx(amountCents: -1500, date: DateTime(2025, 11, 5), description: 'netflix premium'),
            _tx(amountCents: -1500, date: DateTime(2025, 12, 5), description: 'Netflix Premium'),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

        await _open(tester, container, goal: goal, progress: progress);

        // Only the first letter capitalized, the rest of the
        // normalized concept (lowercase) is left as-is: "Netflix premium",
        // not "Netflix Premium" or "netflix premium".
        expect(find.text('Netflix premium'), findsOneWidget);
        expect(find.text('netflix premium'), findsNothing);
        expect(find.text('Netflix Premium'), findsNothing);
      },
    );

    testWidgets('cobertura menor que la necesaria: "podrías cubrir hasta X de los Y"', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          _tx(amountCents: -1500, date: DateTime(2025, 10, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 11, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 12, 5)),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Goal 1,000 €, nothing saved, 1 month: required contribution = 100,000.
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

      await _open(tester, container, goal: goal, progress: progress);

      expect(find.textContaining('Podrías cubrir hasta'), findsOneWidget);
    });

    testWidgets(
      'cobertura menor: el texto de la hoja coincide exactamente con coverageLine del resumen',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: -1500, date: DateTime(2025, 10, 5)),
            _tx(amountCents: -1500, date: DateTime(2025, 11, 5)),
            _tx(amountCents: -1500, date: DateTime(2025, 12, 5)),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));
        final result = await container.read(buildSavingsSuggestionsProvider)(userId: _userId);
        final summary = summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: result);

        await _open(tester, container, goal: goal, progress: progress);

        expect(find.text(summary.coverageLine), findsOneWidget);
      },
    );

    testWidgets('cobertura mayor que la necesaria: lo dice sin "hasta X de Y"', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          _tx(amountCents: -500000, date: DateTime(2025, 10, 5)),
          _tx(amountCents: -500000, date: DateTime(2025, 11, 5)),
          _tx(amountCents: -500000, date: DateTime(2025, 12, 5)),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
          ),
        ],
      );
      addTearDown(container.dispose);
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

      await _open(tester, container, goal: goal, progress: progress);

      expect(find.textContaining('podrías cubrir toda tu aportación mensual'), findsOneWidget);
      expect(find.textContaining('Podrías cubrir hasta'), findsNothing);
    });

    testWidgets(
      'cobertura mayor: el texto de la hoja coincide exactamente con coverageLine del resumen',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: -500000, date: DateTime(2025, 10, 5)),
            _tx(amountCents: -500000, date: DateTime(2025, 11, 5)),
            _tx(amountCents: -500000, date: DateTime(2025, 12, 5)),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));
        final result = await container.read(buildSavingsSuggestionsProvider)(userId: _userId);
        final summary = summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: result);

        await _open(tester, container, goal: goal, progress: progress);

        expect(find.text(summary.coverageLine), findsOneWidget);
      },
    );

    testWidgets(
      'cobertura cero (solo gastos puntuales): mensaje propio, distinto del de "sin histórico suficiente"',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: -800, date: DateTime(2025, 10, 10), category: Category.transporte),
            _tx(amountCents: -900, date: DateTime(2025, 11, 10), category: Category.transporte),
            _tx(amountCents: -1100, date: DateTime(2025, 12, 10), category: Category.transporte),
            _tx(amountCents: -1200, date: DateTime(2025, 12, 20), category: Category.transporte),
            _tx(
              amountCents: -5000,
              date: DateTime(2026, 1, 5),
              category: Category.transporte,
              description: 'Taxi urgente',
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 10))),
            ),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 10));

        await _open(tester, container, goal: goal, progress: progress);

        expect(find.text('Taxi urgente'), findsOneWidget);
        expect(find.textContaining('no cubren nada de tu aportación mensual'), findsOneWidget);
        expect(
          find.text('No hay histórico suficiente en los últimos 3 meses para calcular opciones de ahorro.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'cobertura cero: el texto de la hoja coincide exactamente con coverageLine del resumen',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: -800, date: DateTime(2025, 10, 10), category: Category.transporte),
            _tx(amountCents: -900, date: DateTime(2025, 11, 10), category: Category.transporte),
            _tx(amountCents: -1100, date: DateTime(2025, 12, 10), category: Category.transporte),
            _tx(amountCents: -1200, date: DateTime(2025, 12, 20), category: Category.transporte),
            _tx(
              amountCents: -5000,
              date: DateTime(2026, 1, 5),
              category: Category.transporte,
              description: 'Taxi urgente',
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 10))),
            ),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 10));
        final result = await container.read(buildSavingsSuggestionsProvider)(userId: _userId);
        final summary = summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: result);

        await _open(tester, container, goal: goal, progress: progress);

        expect(find.text(summary.coverageLine), findsOneWidget);
      },
    );

    testWidgets('sin IA: no aparece ningún botón ni sección de redacción', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          _tx(amountCents: -1500, date: DateTime(2025, 10, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 11, 5)),
          _tx(amountCents: -1500, date: DateTime(2025, 12, 5)),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
          ),
        ],
      );
      addTearDown(container.dispose);
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

      await _open(tester, container, goal: goal, progress: progress, showAiButton: false);

      expect(find.text('Redactar resumen con IA'), findsNothing);
      expect(find.textContaining('Texto generado por IA'), findsNothing);
    });

    testWidgets(
      'con IA: redacta el resumen, muestra el texto con su nota y descuenta del contador',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: -1500, date: DateTime(2025, 10, 5)),
            _tx(amountCents: -1500, date: DateTime(2025, 11, 5)),
            _tx(amountCents: -1500, date: DateTime(2025, 12, 5)),
          ],
        );
        final gateway = FakeSavingsSuggestionsGateway.returning('Tienes varias opciones de ahorro disponibles.');
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
            ),
            geminiSavingsSuggestionsGatewayProvider.overrideWithValue(gateway),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

        await _open(tester, container, goal: goal, progress: progress, showAiButton: true);

        expect(find.text('Redactar resumen con IA'), findsOneWidget);
        expect(
          find.text('Te quedan ${ExplainSavingsSuggestions.maxExplanationsPerSession} resúmenes'),
          findsOneWidget,
        );

        await tester.tap(find.text('Redactar resumen con IA'));
        await tester.pumpAndSettle();

        expect(find.text('Tienes varias opciones de ahorro disponibles.'), findsOneWidget);
        expect(find.text('Texto generado por IA a partir de las cifras de arriba.'), findsOneWidget);
        expect(
          find.text('Te quedan ${ExplainSavingsSuggestions.maxExplanationsPerSession - 1} resúmenes'),
          findsOneWidget,
        );
        expect(gateway.callCount, 1);
      },
    );

    testWidgets('con IA: el contador usa el singular correcto cuando queda 1', (tester) async {
      final repository = FakeTransactionRepository();
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 1, 1))),
          ),
          geminiSavingsSuggestionsGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));
      final suggestions = await container.read(buildSavingsSuggestionsProvider)(userId: _userId);

      // Spends all summaries but 1 by calling the use case already
      // resolved by the provider directly (without going through the
      // UI): it's the same as pressing the button repeatedly, but
      // without the fragility of opening and closing the modal sheet
      // in a loop. A different goal (same `id` changed) on each round
      // so none of them hit the cache and all of them count toward the quota.
      final explain = container.read(explainSavingsSuggestionsProvider(_userId));
      for (var i = 0; i < ExplainSavingsSuggestions.maxExplanationsPerSession - 1; i++) {
        await explain(goal: goal.copyWith(id: 'g$i'), progress: progress, suggestions: suggestions);
      }
      expect(explain.remainingExplanations, 1);

      await _open(tester, container, goal: goal, progress: progress, showAiButton: true);

      expect(find.text('Te queda 1 resumen'), findsOneWidget);
    });

    testWidgets(
      'aislamiento: el usuario B no hereda el texto cacheado ni el contador gastado de A',
      (tester) async {
        final repositoryA = FakeTransactionRepository();
        final gatewayA = FakeSavingsSuggestionsGateway.returning('Resumen de A');
        final container = ProviderContainer(
          overrides: [
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(repositoryA, FakeClock(DateTime(2026, 1, 1))),
            ),
            geminiSavingsSuggestionsGatewayProvider.overrideWithValue(gatewayA),
          ],
        );
        addTearDown(container.dispose);
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));
        final params = _OpenParams(userId: 'user-A', goal: goal, progress: progress, showAiButton: true);

        await _pumpMultiOpenApp(tester, container, params);
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Redactar resumen con IA'));
        await tester.pumpAndSettle();
        expect(find.text('Resumen de A'), findsOneWidget);
        expect(
          find.text('Te quedan ${ExplainSavingsSuggestions.maxExplanationsPerSession - 1} resúmenes'),
          findsOneWidget,
        );

        // Closes A's sheet and opens one for B, on the same widget
        // tree (see `_OpenParams`/`_reopen`).
        params.userId = 'user-B';
        await _reopen(tester);

        expect(find.text('Resumen de A'), findsNothing);
        expect(
          find.text('Te quedan ${ExplainSavingsSuggestions.maxExplanationsPerSession} resúmenes'),
          findsOneWidget,
        );
      },
    );

    testWidgets('si el cálculo falla, muestra un mensaje genérico', (tester) async {
      final container = ProviderContainer(
        overrides: [
          buildSavingsSuggestionsProvider.overrideWithValue(
            BuildSavingsSuggestions(_ThrowingTransactionRepository(), FakeClock(DateTime(2026, 1, 1))),
          ),
        ],
      );
      addTearDown(container.dispose);
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

      await _open(tester, container, goal: goal, progress: progress);

      expect(
        find.text('No se han podido calcular las opciones de ahorro. Inténtalo de nuevo más tarde.'),
        findsOneWidget,
      );
    });
  });
}

class _ThrowingTransactionRepository extends FakeTransactionRepository {
  @override
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  }) {
    throw Exception('fallo simulado');
  }
}
