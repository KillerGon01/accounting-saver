import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/common/session_feedback_providers.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:accounting_saver/presentation/transactions/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Future<void> _pump(WidgetTester tester, FakeTransactionRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
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

    // 360x640 (instead of 360x740) leaves, with the keyboard open (300px
    // inset), only 44px for the transactions list (284px body minus
    // 64px for `_MonthNavigator` and 176px for the summary card): exactly
    // what the day header takes up, with no room for any `ListTile`
    // (~56-72px), so that widget never gets built inside the `ListView`
    // and the test would fail even without an overflow. 360x740 is
    // still a real small phone (e.g. Pixel 6a in logical dp), but leaves
    // plenty of margin for the row.
    for (final size in [const Size(360, 740), const Size(407, 904)]) {
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

  group('búsqueda y filtros', () {
    Future<void> addTwoTransactions(FakeTransactionRepository repository) async {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day, 12);
      await repository.add(
        userId: _userId,
        transaction: Transaction(
          id: 'cafe',
          amountCents: -250,
          date: day,
          description: 'Café con Marta',
          categoryId: Category.restaurantes,
          source: TransactionSource.manual,
          createdAt: day,
        ),
      );
      await repository.add(
        userId: _userId,
        transaction: Transaction(
          id: 'gasolina',
          amountCents: -4000,
          date: day,
          description: 'Gasolina',
          categoryId: Category.transporte,
          source: TransactionSource.manual,
          createdAt: day,
        ),
      );
    }

    testWidgets('sin filtros no muestra ningún indicador ni insignia en el icono', (tester) async {
      final repository = FakeTransactionRepository();
      await addTwoTransactions(repository);
      await _pump(tester, repository);

      expect(find.text('Café con Marta'), findsOneWidget);
      expect(find.text('Gasolina'), findsOneWidget);
      expect(find.textContaining('movimientos', findRichText: true), findsNothing);
      expect(find.byTooltip('Buscar y filtrar'), findsOneWidget);
      expect(find.byTooltip('Buscar y filtrar (filtros activos)'), findsNothing);
    });

    testWidgets(
      'al buscar por texto (ignorando tildes y mayúsculas), filtra la lista y muestra '
      '"N de M movimientos" con una insignia en el icono',
      (tester) async {
        final repository = FakeTransactionRepository();
        await addTwoTransactions(repository);
        await _pump(tester, repository);

        await tester.tap(find.byTooltip('Buscar y filtrar'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, 'Buscar por concepto'), 'CAFÉ');
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();

        expect(find.text('Café con Marta'), findsOneWidget);
        expect(find.text('Gasolina'), findsNothing);
        expect(find.text('1 de 2 movimientos'), findsOneWidget);
        expect(find.byTooltip('Buscar y filtrar (filtros activos)'), findsOneWidget);
        expect(find.byTooltip('Buscar y filtrar'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'sin ningún movimiento que coincida, muestra el estado vacío filtrado y "Quitar '
      'filtros" lo deshace',
      (tester) async {
        final repository = FakeTransactionRepository();
        await addTwoTransactions(repository);
        await _pump(tester, repository);

        await tester.tap(find.byTooltip('Buscar y filtrar'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Buscar por concepto'),
          'no existe',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();

        expect(
          find.text('Ningún movimiento coincide con la búsqueda o los filtros'),
          findsOneWidget,
        );
        expect(find.text('Café con Marta'), findsNothing);
        expect(find.text('Gasolina'), findsNothing);
        // The empty-state button (not the one in the "N of M" bar) is
        // enough to check it removes the filter.
        await tester.tap(find.widgetWithText(OutlinedButton, 'Quitar filtros'));
        await tester.pumpAndSettle();

        expect(find.text('Café con Marta'), findsOneWidget);
        expect(find.text('Gasolina'), findsOneWidget);
        expect(find.byTooltip('Buscar y filtrar'), findsOneWidget);
      },
    );

    testWidgets('cambiar de mes reinicia los filtros', (tester) async {
      final repository = FakeTransactionRepository();
      await addTwoTransactions(repository);
      await _pump(tester, repository);

      await tester.tap(find.byTooltip('Buscar y filtrar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Buscar por concepto'), 'café');
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 2 movimientos'), findsOneWidget);

      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('1 de 2 movimientos'), findsNothing);
      expect(find.byTooltip('Buscar y filtrar'), findsOneWidget);
      expect(find.byTooltip('Buscar y filtrar (filtros activos)'), findsNothing);
    });
  });

  group('cerrar sesión (icono "Cerrar sesión")', () {
    testWidgets('con éxito, deja signedOut en sessionFeedbackProvider', (tester) async {
      final repository = FakeTransactionRepository();
      final authRepository = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(authRepository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: appLocale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: const TransactionsScreen(userId: _userId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pump();

      expect(container.read(sessionFeedbackProvider), SessionFeedbackKind.signedOut);
    });

    testWidgets('si falla, muestra el error y no deja ningún aviso', (tester) async {
      final repository = FakeTransactionRepository();
      final authRepository = FakeAuthRepository(
        signOutError: const AuthException('network-request-failed'),
      );
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(authRepository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: appLocale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: const TransactionsScreen(userId: _userId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No se pudo cerrar la sesión'), findsOneWidget);
      expect(container.read(sessionFeedbackProvider), isNull);
    });
  });

  testWidgets('al pulsar "Nuevo" con un aviso visible, oculta el SnackBar antes de navegar', (tester) async {
    await _pump(tester, FakeTransactionRepository());

    // "Cargar datos de ejemplo" leaves a SnackBar visible (see
    // `_showMessage` in `TransactionsScreen`), with floating behavior
    // anchored above the "Nuevo" FAB (see docs/design.md, "Aviso
    // estable al navegar").
    await tester.tap(find.widgetWithText(FilledButton, 'Cargar datos de ejemplo'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}
