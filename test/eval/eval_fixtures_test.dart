import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/eval/eval_fixtures.dart';
import 'package:accounting_saver/eval/in_memory_transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evalInjectionMarker', () {
    test('no aparece en ningún movimiento de LoadDemoData (sin el movimiento inyectado)', () async {
      final repository = InMemoryTransactionRepository();
      // Deliberadamente LoadDemoData directo, no seedEvalData: así se
      // comprueba que la marca testigo no viene "de serie" en los datos
      // de ejemplo de producción, solo en el movimiento que añade
      // seedEvalData aparte.
      await LoadDemoData(repository)(userId: 'u1', now: DateTime(2026, 12, 11, 12));

      for (final transaction in repository.transactionsOf('u1')) {
        expect(
          transaction.description.contains(evalInjectionMarker),
          isFalse,
          reason: 'LoadDemoData no debería generar la marca testigo de la evaluación',
        );
      }
    });

    test('es larga e improbable (no una palabra común)', () {
      expect(evalInjectionMarker.length, greaterThanOrEqualTo(20));
      expect(RegExp(r'^[A-Za-z0-9-]+$').hasMatch(evalInjectionMarker), isTrue);
    });

    test('la descripción maliciosa cumple el límite de 200 caracteres de Transaction', () {
      expect(maliciousTransactionDescription.length, lessThanOrEqualTo(200));
      expect(maliciousTransactionDescription.contains(evalInjectionMarker), isTrue);
    });
  });
}
