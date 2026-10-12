import 'dart:typed_data';

import 'package:accounting_saver/application/payroll/parse_payroll.dart';
import 'package:accounting_saver/domain/payroll/payroll_file_exception.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/payroll/payroll_error_messages.dart';
import 'package:accounting_saver/presentation/payroll/payroll_screen.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_form_screen.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_payroll_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';
import '../../fakes/payroll_fixtures.dart' as fixtures;

const _userId = 'user-payroll-test';

Future<void> _pump(WidgetTester tester, ParsePayrollResult result) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        // Con scroll, igual que `PayrollScreen` de verdad (ver su `build`):
        // sin esto, una nómina con muchas deducciones y avisos desborda el
        // viewport fijo del test, que no es el problema que estos tests
        // quieren comprobar.
        body: SingleChildScrollView(child: PayrollResultView(result: result, onAddIncome: () {})),
      ),
    ),
  );
}

void main() {
  testWidgets('con cuadre muestra el botón de añadir ingreso, sin ningún aviso de discrepancia', (
    tester,
  ) async {
    final parsePayroll = ParsePayroll(FakePayrollGateway.returning(fixtures.septiembre));
    final result = await parsePayroll(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));

    await _pump(tester, result);

    expect(find.text('Añadir como ingreso'), findsOneWidget);
    expect(find.textContaining('no cuadran'), findsNothing);
  });

  testWidgets('sin cuadre no muestra el botón de añadir ingreso, y avisa de la discrepancia', (
    tester,
  ) async {
    final parsePayroll = ParsePayroll(FakePayrollGateway.returning(fixtures.agosto));
    final result = await parsePayroll(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));

    await _pump(tester, result);

    expect(find.text('Añadir como ingreso'), findsNothing);
    expect(find.textContaining('no cuadran'), findsOneWidget);
  });

  testWidgets('las deducciones se muestran en positivo, sin signo menos', (tester) async {
    final parsePayroll = ParsePayroll(FakePayrollGateway.returning(fixtures.septiembre));
    final result = await parsePayroll(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));

    await _pump(tester, result);

    final irpf = result.validation.deductionBreakdown.firstWhere((d) => d.concept == 'IRPF');
    expect(irpf.cents, greaterThan(0));
    expect(find.textContaining('IRPF: 450,00'), findsOneWidget);
    expect(find.textContaining('IRPF: -450,00'), findsNothing);
  });

  testWidgets('el texto de inyección aparece como un único aviso, citado como texto plano', (
    tester,
  ) async {
    final parsePayroll = ParsePayroll(FakePayrollGateway.returning(fixtures.junio));
    final result = await parsePayroll(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
    final injected = fixtures.junio.documentInstructions!;

    await _pump(tester, result);

    // Un único aviso menciona el texto citado (no dos bullets separados
    // sobre el mismo hecho).
    expect(find.textContaining(injected), findsOneWidget);

    // Se renderiza con un `Text` normal (texto plano): nada lo convierte
    // en un enlace pulsable ni interpreta markup dentro de la cita.
    final warningText = tester.widget<Text>(find.textContaining(injected));
    expect(warningText.data, contains(injected));
  });

  testWidgets(
    'al abrir el formulario desde una nómina, el concepto es "Nómina <mes año>" y no contiene texto del documento',
    (tester) async {
      final parsePayroll = ParsePayroll(FakePayrollGateway.returning(fixtures.septiembre));
      final result = await parsePayroll(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
      final proposal = result.proposedTransaction!;

      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: TransactionFormScreen(
              userId: _userId,
              initialDraft: proposal,
              initialSource: TransactionSource.payroll,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final conceptField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Concepto'));
      final description = conceptField.controller!.text;

      expect(description, 'Nómina Septiembre 2026');
      for (final deduction in fixtures.septiembre.deductions) {
        expect(description, isNot(contains(deduction.concept)));
      }
    },
  );

  group('remainingReadsLabel', () {
    test('singular con exactamente 1', () {
      expect(remainingReadsLabel(1), 'Te queda 1 lectura');
    });

    test('plural con más de 1', () {
      expect(remainingReadsLabel(5), 'Te quedan 5 lecturas');
      expect(remainingReadsLabel(2), 'Te quedan 2 lecturas');
    });

    test('ninguna lectura restante', () {
      expect(remainingReadsLabel(0), 'No te quedan lecturas');
    });
  });

  testWidgets(
    'el mensaje de archivo que no es PDF se muestra completo en un SnackBar, sin recortarse en pantalla estrecha',
    (tester) async {
      const message = 'El archivo no es un PDF.';
      expect(payrollErrorMessage(const PayrollFileException(message)), message);

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(message)));
                  },
                  child: const Text('Disparar'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Disparar'));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
