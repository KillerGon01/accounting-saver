import 'package:accounting_saver/application/savings/build_savings_suggestions.dart';
import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/savings/savings_goal_providers.dart';
import 'package:accounting_saver/presentation/savings/savings_goals_screen.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_savings_goal_repository.dart';
import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  String userId = _userId,
  required FakeClock clock,
}) async {
  // Un widget intermedio (no `SavingsGoalsScreen`) antes del de cada
  // usuario, para que Flutter la desmonte de verdad en vez de reutilizar
  // su `State` con otro `userId` — mismo motivo que en
  // `chat_screen_test.dart` (así reproduce "cerrar sesión y entrar con
  // otra cuenta sin reiniciar la app", como hace `AuthGate`).
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MaterialApp(home: SizedBox.shrink())),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: SavingsGoalsScreen(userId: userId, clock: clock),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SavingsGoalsScreen', () {
    testWidgets('estado vacío: sin metas, muestra el aviso y el botón de crear', (tester) async {
      final container = ProviderContainer(
        overrides: [savingsGoalRepositoryProvider.overrideWithValue(FakeSavingsGoalRepository())],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

      expect(find.text('Todavía no tienes ninguna meta de ahorro'), findsOneWidget);
      expect(find.text('Nueva meta'), findsWidgets);
    });

    testWidgets(
      'con una meta, muestra el progreso: porcentaje, importes, estado y fecha límite',
      (tester) async {
        final repository = FakeSavingsGoalRepository();
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g1',
            name: 'Vacaciones',
            targetCents: 100000,
            savedCents: 50000,
            deadline: DateTime(2027, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final container = ProviderContainer(
          overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

        expect(find.text('Vacaciones'), findsOneWidget);
        expect(find.textContaining('50 %'), findsOneWidget);
        expect(find.textContaining(formatCents(50000)), findsOneWidget); // ahorrado
        expect(find.textContaining(formatCents(100000)), findsOneWidget); // objetivo
        expect(find.text('En camino'), findsOneWidget);
      },
    );

    testWidgets('al pasar a "Cumplida", el icono de estado da un pequeño rebote, solo esa vez', (tester) async {
      final repository = FakeSavingsGoalRepository();
      final goal = SavingsGoal(
        id: 'g1',
        name: 'Vacaciones',
        targetCents: 100000,
        savedCents: 90000,
        deadline: DateTime(2027, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      await repository.add(userId: _userId, goal: goal);
      final container = ProviderContainer(
        overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      // Localizado dentro de la tarjeta de esta meta: puede haber otros
      // `ScaleTransition` en el árbol (p. ej. de material propio de
      // Flutter) ajenos a la celebración.
      Finder scaleTransitionOfCard() => find.descendant(
        of: find.ancestor(of: find.text('Vacaciones'), matching: find.byType(Card)),
        matching: find.byType(ScaleTransition),
      );

      await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));
      expect(find.text('En camino'), findsOneWidget);
      expect(tester.widget<ScaleTransition>(scaleTransitionOfCard()).scale.value, 1.0);

      await repository.update(userId: _userId, goal: goal.copyWith(savedCents: 100000));
      await tester.pump(); // procesa el stream y reconstruye con el nuevo estado
      await tester.pump(const Duration(milliseconds: 150)); // a mitad del rebote (400 ms)

      expect(
        tester.widget<ScaleTransition>(scaleTransitionOfCard()).scale.value,
        greaterThan(1.0),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cumplida'), findsOneWidget);
      expect(tester.widget<ScaleTransition>(scaleTransitionOfCard()).scale.value, 1.0);
    });

    testWidgets('alta: crea una meta nueva desde el formulario y aparece en la lista', (tester) async {
      final repository = FakeSavingsGoalRepository();
      final container = ProviderContainer(
        overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

      await tester.tap(find.text('Nueva meta').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Coche nuevo');
      await tester.enterText(find.widgetWithText(TextFormField, 'Importe objetivo'), '5000');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Coche nuevo'), findsOneWidget);
      expect(repository.goalsOf(_userId), hasLength(1));
      expect(repository.goalsOf(_userId).single.targetCents, 500000);
    });

    testWidgets(
      'validaciones: nombre vacío e importe inválido muestran error y no guardan nada',
      (tester) async {
        final repository = FakeSavingsGoalRepository();
        final container = ProviderContainer(
          overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));
        await tester.tap(find.text('Nueva meta').first);
        await tester.pumpAndSettle();

        // Nombre vacío. "abc" no sirve para el importe: los
        // `inputFormatters` del campo ya lo filtrarían a vacío antes de
        // llegar al validador. "12,345" pasa el filtro de caracteres
        // permitidos pero no el de `parseEurosToCents` (como mucho 2
        // decimales).
        await tester.enterText(find.widgetWithText(TextFormField, 'Importe objetivo'), '12,345');
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
        await tester.pumpAndSettle();

        expect(find.text('Introduce un nombre'), findsOneWidget);
        expect(find.text('Formato no válido, por ejemplo 1.500,00'), findsOneWidget);
        expect(repository.goalsOf(_userId), isEmpty);

        // Importe en 0: formato válido, pero no mayor que 0.
        await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Meta');
        await tester.enterText(find.widgetWithText(TextFormField, 'Importe objetivo'), '0');
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
        await tester.pumpAndSettle();

        expect(find.text('El importe objetivo debe ser mayor que 0'), findsOneWidget);
        expect(repository.goalsOf(_userId), isEmpty);
      },
    );

    testWidgets('borrado con confirmación: cancelar no borra, confirmar sí', (tester) async {
      final repository = FakeSavingsGoalRepository();
      await repository.add(
        userId: _userId,
        goal: SavingsGoal(
          id: 'g1',
          name: 'Meta a borrar',
          targetCents: 100000,
          savedCents: 0,
          deadline: DateTime(2027, 1, 1),
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final container = ProviderContainer(
        overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Meta a borrar'), findsOneWidget);
      expect(repository.goalsOf(_userId), hasLength(1));

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar').last);
      await tester.pumpAndSettle();

      expect(find.text('Meta a borrar'), findsNothing);
      expect(repository.goalsOf(_userId), isEmpty);
    });

    testWidgets('aislamiento: cerrar sesión y entrar con otra cuenta no comparte metas', (tester) async {
      final repository = FakeSavingsGoalRepository();
      await repository.add(
        userId: 'user-A',
        goal: SavingsGoal(
          id: 'gA',
          name: 'Meta de A',
          targetCents: 100000,
          savedCents: 0,
          deadline: DateTime(2027, 1, 1),
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final container = ProviderContainer(
        overrides: [savingsGoalRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, userId: 'user-A', clock: FakeClock(DateTime(2026, 1, 1)));
      expect(find.text('Meta de A'), findsOneWidget);

      // "Cierre de sesión y entrada de B": mismo container, pantalla nueva.
      await _pump(tester, container, userId: 'user-B', clock: FakeClock(DateTime(2026, 1, 1)));

      expect(find.text('Meta de A'), findsNothing);
      expect(find.text('Todavía no tienes ninguna meta de ahorro'), findsOneWidget);
    });

    testWidgets(
      '"¿De dónde puedo ahorrar?" solo aparece para metas en camino o por detrás, '
      'no para cumplidas ni vencidas',
      (tester) async {
        final repository = FakeSavingsGoalRepository();
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g-on-track',
            name: 'En camino',
            targetCents: 100000,
            savedCents: 0,
            deadline: DateTime(2027, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g-completed',
            name: 'Meta cumplida',
            targetCents: 100000,
            savedCents: 100000,
            deadline: DateTime(2027, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g-overdue',
            name: 'Meta vencida',
            targetCents: 100000,
            savedCents: 0,
            deadline: DateTime(2025, 1, 1),
            createdAt: DateTime(2024, 1, 1),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            savingsGoalRepositoryProvider.overrideWithValue(repository),
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(FakeTransactionRepository(), FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

        expect(find.text('¿De dónde puedo ahorrar?'), findsOneWidget);
        expect(find.text('Meta cumplida'), findsOneWidget);
        expect(find.text('Meta vencida'), findsOneWidget);
      },
    );

    testWidgets(
      'la hoja de sugerencias muestra el aviso fijo y, sin histórico, su propio estado vacío',
      (tester) async {
        final repository = FakeSavingsGoalRepository();
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g1',
            name: 'Vacaciones',
            targetCents: 100000,
            savedCents: 0,
            deadline: DateTime(2027, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            savingsGoalRepositoryProvider.overrideWithValue(repository),
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(FakeTransactionRepository(), FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

        await tester.tap(find.text('¿De dónde puedo ahorrar?'));
        await tester.pumpAndSettle();

        expect(
          find.text('No hay histórico suficiente en los últimos 3 meses para calcular opciones de ahorro.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'la hoja de sugerencias, con histórico, muestra las opciones y el total cubierto',
      (tester) async {
        final repository = FakeSavingsGoalRepository();
        await repository.add(
          userId: _userId,
          goal: SavingsGoal(
            id: 'g1',
            name: 'Vacaciones',
            targetCents: 100000,
            savedCents: 0,
            deadline: DateTime(2026, 2, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final transactionRepository = FakeTransactionRepository();
        await transactionRepository.addAll(
          userId: _userId,
          transactions: [
            Transaction(
              id: 'tx-1',
              amountCents: -1500,
              date: DateTime(2025, 10, 5),
              description: 'Netflix',
              categoryId: Category.suscripciones,
              source: TransactionSource.manual,
              createdAt: DateTime(2025, 10, 5),
            ),
            Transaction(
              id: 'tx-2',
              amountCents: -1500,
              date: DateTime(2025, 11, 5),
              description: 'Netflix',
              categoryId: Category.suscripciones,
              source: TransactionSource.manual,
              createdAt: DateTime(2025, 11, 5),
            ),
            Transaction(
              id: 'tx-3',
              amountCents: -1500,
              date: DateTime(2025, 12, 5),
              description: 'Netflix',
              categoryId: Category.suscripciones,
              source: TransactionSource.manual,
              createdAt: DateTime(2025, 12, 5),
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            savingsGoalRepositoryProvider.overrideWithValue(repository),
            buildSavingsSuggestionsProvider.overrideWithValue(
              BuildSavingsSuggestions(transactionRepository, FakeClock(DateTime(2026, 1, 1))),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, clock: FakeClock(DateTime(2026, 1, 1)));

        await tester.tap(find.text('¿De dónde puedo ahorrar?'));
        await tester.pumpAndSettle();

        expect(find.text('Netflix'), findsOneWidget);
        expect(find.textContaining('Decidir qué recortar es cosa tuya'), findsOneWidget);
      },
    );
  });
}
