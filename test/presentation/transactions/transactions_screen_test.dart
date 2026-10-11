import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:accounting_saver/presentation/transactions/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Future<void> _pump(WidgetTester tester, FakeTransactionRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const TransactionsScreen(userId: _userId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el estado vacío con el botón de datos de ejemplo', (tester) async {
    await _pump(tester, FakeTransactionRepository());

    expect(find.text('No hay movimientos este mes'), findsOneWidget);
    expect(find.text('Cargar datos de ejemplo'), findsWidgets);
  });

  testWidgets('agrupa por día y muestra el balance del mes', (tester) async {
    final repository = FakeTransactionRepository();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day, 12);
    await repository.add(
      userId: _userId,
      transaction: Transaction(
        id: 'nomina',
        amountCents: 200000,
        date: day,
        description: 'Nómina',
        categoryId: Category.nomina,
        source: TransactionSource.manual,
        createdAt: day,
      ),
    );
    await repository.add(
      userId: _userId,
      transaction: Transaction(
        id: 'cena',
        amountCents: -2550,
        date: day,
        description: 'Cena',
        categoryId: Category.restaurantes,
        source: TransactionSource.manual,
        createdAt: day,
      ),
    );

    await _pump(tester, repository);

    expect(find.text(formatDayHeader(day)), findsOneWidget);
    expect(find.text(formatCents(200000 - 2550)), findsOneWidget);
    expect(find.text(formatCents(200000)), findsNWidgets(2));
    expect(find.text(formatCents(-2550)), findsNWidgets(2));
    expect(find.byTooltip('Mes anterior'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
  });

  group('pantalla pequeña con el teclado abierto', () {
    Future<void> withKeyboard(
      WidgetTester tester,
      Size size,
      Future<void> Function() body,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await body();
    }

    for (final size in [const Size(360, 640), const Size(407, 904)]) {
      testWidgets(
        'estado vacío sin desbordamiento en ${size.width.toInt()}x${size.height.toInt()} con teclado',
        (tester) async {
          await withKeyboard(tester, size, () async {
            await _pump(tester, FakeTransactionRepository());

            expect(find.text('No hay movimientos este mes'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );

      testWidgets(
        'con movimientos sin desbordamiento en ${size.width.toInt()}x${size.height.toInt()} con teclado',
        (tester) async {
          final repository = FakeTransactionRepository();
          final today = DateTime.now();
          final day = DateTime(today.year, today.month, today.day, 12);
          await repository.add(
            userId: _userId,
            transaction: Transaction(
              id: 'cena',
              amountCents: -2550,
              date: day,
              description: 'Cena',
              categoryId: Category.restaurantes,
              source: TransactionSource.manual,
              createdAt: day,
            ),
          );

          await withKeyboard(tester, size, () async {
            await _pump(tester, repository);

            expect(find.text('Cena'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );
    }
  });
}
