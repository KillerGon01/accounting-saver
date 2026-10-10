import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/reports/monthly_report_screen.dart';
import 'package:accounting_saver/presentation/reports/report_providers.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_monthly_report_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

const _userId = 'u1';

/// `formatCents` (`lib/presentation/transactions/formatters.dart`) separa
/// los euros del símbolo con un espacio NO separable (` `), no un
/// espacio normal: hay que reproducirlo aquí para que `find.text` acierte
/// con el texto exacto que renderiza la pantalla.
String _eur(String amount) => '$amount €';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool? showAiComment,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MonthlyReportScreen(userId: _userId, showAiComment: showAiComment),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Transaction _tx({
  required int amountCents,
  required DateTime date,
  Category category = Category.otros,
  String id = 'tx-1',
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: date,
    description: 'movimiento',
    categoryId: category,
    source: TransactionSource.manual,
    createdAt: date,
  );
}

void main() {
  final now = DateTime.now();

  group('con IA', () {
    testWidgets('botón visible, genera un comentario y descuenta el contador', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final gateway = FakeMonthlyReportGateway.returning('Has gastado 20,00 € en ocio este mes.');
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          monthlyReportGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);

      expect(find.text('Generar comentario con IA'), findsOneWidget);
      expect(find.text('Te quedan 3 comentarios'), findsOneWidget);

      await tester.ensureVisible(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();

      expect(find.text('Has gastado 20,00 € en ocio este mes.'), findsOneWidget);
      expect(find.text('Te quedan 2 comentarios'), findsOneWidget);
    });

    testWidgets('indicador de progreso con avisos a los 10s y 45s, sin bloquear la app', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final gateway = FakeMonthlyReportGateway.pending();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          monthlyReportGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);
      await tester.ensureVisible(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar comentario con IA'));
      await tester.pump();

      expect(find.text('Generando el comentario...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Generando el comentario... Esto está tardando más de lo normal...'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 35));
      expect(
        find.text(
          'Generando el comentario... Esto está tardando más de lo normal... '
          'Puede tardar hasta un par de minutos.',
        ),
        findsOneWidget,
      );

      gateway.complete('Comentario final');
      await tester.pumpAndSettle();

      expect(find.text('Comentario final'), findsOneWidget);
    });

    testWidgets('un mes sin movimientos muestra el aviso en vez del botón', (tester) async {
      final repository = FakeTransactionRepository();
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);

      expect(find.text('No hay movimientos este mes'), findsOneWidget);
      expect(find.text('Generar comentario con IA'), findsNothing);
    });
  });

  group('sin IA', () {
    testWidgets('no muestra el botón ni el contador, pero sí los datos del mes', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: false);

      expect(find.text('Generar comentario con IA'), findsNothing);
      expect(find.textContaining('comentarios'), findsNothing);
      expect(find.text('Gasto por categoría'), findsOneWidget);
    });
  });

  testWidgets('un informe truncado muestra el aviso de informe parcial', (tester) async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: _userId,
      transactions: [
        for (var i = 1; i <= 2005; i++)
          _tx(
            id: 'tx-$i',
            amountCents: -1,
            date: DateTime(now.year, now.month, 1).add(Duration(minutes: i)),
          ),
      ],
    );
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.textContaining('Informe parcial'), findsOneWidget);
  });

  testWidgets('el mes en curso muestra hasta qué día llegan los datos', (tester) async {
    final repository = FakeTransactionRepository();
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.textContaining('Mes en curso, hasta el día ${now.day}'), findsOneWidget);
  });

  testWidgets('un movimiento nuevo cambia las cifras del informe sin reiniciar la pantalla', (tester) async {
    final repository = FakeTransactionRepository();
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.text(_eur('0,00')), findsWidgets); // ingresos y gastos a cero

    await container.read(addTransactionProvider)(
      userId: _userId,
      transaction: _tx(amountCents: -5000, date: DateTime(now.year, now.month, 2), category: Category.ocio),
    );
    await tester.pumpAndSettle();

    expect(find.text(_eur('-50,00')), findsOneWidget); // balance del mes
    // "50,00 €" aparece dos veces: en el total de gastos y en la fila de
    // la categoría del gráfico (el único gasto del mes).
    expect(find.text(_eur('50,00')), findsNWidgets(2));
  });
}
