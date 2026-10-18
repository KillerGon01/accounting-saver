import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction_filter.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:accounting_saver/presentation/transactions/transaction_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a `Scaffold` with a button that opens the sheet
/// (`showTransactionFilterSheet` needs a real `Navigator`/`Overlay`, the
/// sheet can't be pumped on its own). [onResult] receives whatever the
/// sheet returns on close (`null` if dismissed without pressing
/// "Aplicar" or "Limpiar").
Future<void> _pumpHost(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  double textScale = 1.0,
  required TransactionFilter initial,
  required void Function(TransactionFilter? result) onResult,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showTransactionFilterSheet(context, current: initial);
              onResult(result);
            },
            child: const Text('Abrir filtros'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Abrir filtros'));
  await tester.pumpAndSettle();
}

void main() {
  group('showTransactionFilterSheet', () {
    testWidgets('pre-rellena los campos con el filtro actual', (tester) async {
      await _pumpHost(
        tester,
        initial: TransactionFilter(
          searchText: 'café',
          categoryId: Category.restaurantes,
          kind: TransactionKind.expense,
          minAmountCents: 1000,
          maxAmountCents: 5000,
        ),
        onResult: (_) {},
      );
      await _open(tester);

      expect(find.text('café'), findsOneWidget);
      expect(find.text(Category.restaurantes.label), findsOneWidget);
      expect(find.text(formatEditableAmount(1000)), findsOneWidget);
      expect(find.text(formatEditableAmount(5000)), findsOneWidget);
    });

    testWidgets('Aplicar devuelve un TransactionFilter con los valores editados', (tester) async {
      TransactionFilter? result;
      await _pumpHost(tester, initial: TransactionFilter(), onResult: (value) => result = value);
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Buscar por concepto'), 'gasolina');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mínimo'), '10');
      await tester.enterText(find.widgetWithText(TextFormField, 'Máximo'), '50');

      final categoryField = find.widgetWithText(DropdownButtonFormField<Category?>, 'Categoría');
      await tester.ensureVisible(categoryField);
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      await tester.tap(find.text(Category.transporte.label).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gasto'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.searchText, 'gasolina');
      expect(result!.categoryId, Category.transporte);
      expect(result!.kind, TransactionKind.expense);
      expect(result!.minAmountCents, 1000);
      expect(result!.maxAmountCents, 5000);
    });

    testWidgets(
      'muestra un error y no cierra la hoja si un importe no tiene un formato válido',
      (tester) async {
        TransactionFilter? result;
        var resultCallbackCalled = false;
        await _pumpHost(
          tester,
          initial: TransactionFilter(),
          onResult: (value) {
            resultCallbackCalled = true;
            result = value;
          },
        );
        await _open(tester);

        // "abc" doesn't work here: the field's `inputFormatters` would
        // already filter it down to empty before reaching the
        // validator. "12,345" passes the allowed-character format but
        // not `parseEurosToCents`'s (at most 2 decimals).
        await tester.enterText(find.widgetWithText(TextFormField, 'Mínimo'), '12,345');
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();

        expect(find.text('Formato no válido, por ejemplo 12,50'), findsOneWidget);
        expect(resultCallbackCalled, isFalse);
        expect(result, isNull);
      },
    );

    testWidgets('muestra un error si el mínimo es mayor que el máximo', (tester) async {
      var resultCallbackCalled = false;
      await _pumpHost(tester, initial: TransactionFilter(), onResult: (_) => resultCallbackCalled = true);
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Mínimo'), '50');
      await tester.enterText(find.widgetWithText(TextFormField, 'Máximo'), '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('El máximo no puede ser menor que el mínimo'), findsOneWidget);
      expect(resultCallbackCalled, isFalse);
    });

    testWidgets('Limpiar devuelve un filtro vacío de inmediato', (tester) async {
      TransactionFilter? result;
      await _pumpHost(
        tester,
        initial: TransactionFilter(searchText: 'café', categoryId: Category.ocio),
        onResult: (value) => result = value,
      );
      await _open(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Limpiar'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isActive, isFalse);
    });

    // Requested adjustment: 360x640 (the main screen uses 360x740, see
    // transactions_screen_test.dart; this sheet is a different
    // interaction path, with its own margin, so it's tested separately
    // instead of reusing that fixture) with the simulated keyboard (300
    // px inset) and the system text scale at 1.3 — no overflow exception.
    testWidgets(
      'sin excepciones de desbordamiento a 360x640, teclado de 300px y texto a escala 1.3',
      (tester) async {
        await _pumpHost(
          tester,
          size: const Size(360, 640),
          textScale: 1.3,
          initial: TransactionFilter(
            searchText: 'café',
            categoryId: Category.suscripciones,
            kind: TransactionKind.income,
            minAmountCents: 100,
            maxAmountCents: 500000,
          ),
          onResult: (_) {},
        );
        await _open(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.widgetWithText(TextFormField, 'Buscar por concepto'));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        await tester.enterText(find.widgetWithText(TextFormField, 'Buscar por concepto'), 'gasolina');
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
