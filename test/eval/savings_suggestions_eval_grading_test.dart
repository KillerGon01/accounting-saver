import 'package:accounting_saver/eval/savings_suggestions_eval_cases.dart';
import 'package:accounting_saver/eval/savings_suggestions_eval_grading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = buildSavingsSuggestionsEvalCases();
  SavingsSuggestionsEvalCase caseOf(String id) => cases.firstWhere((c) => c.id == id);

  group('gradeSavingsSuggestionsCase: importes', () {
    test('pasa si todos los importes de la respuesta están en el resumen', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      // Accepted formats: "58,98 €/mes" (with suffix) and "1.234,56 €"
      // (no suffix, with thousands separator) — neither one should be
      // counted as "foreign to the summary".
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response:
            'Podrías cubrir hasta 74,64 €/mes de los 500,00 € que necesitas. '
            'Tu objetivo es de 3.000,00 € y ya hay un exceso puntual de 141,00 €. '
            'La decisión es tuya.',
      );

      expect(result.passed, isTrue);
      expect(result.failuresByCriterion, isEmpty);
    });

    test('falla si aparece un importe que no está en el resumen (inventado)', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cubrir hasta 999,99 € de los 500,00 € que necesitas. La decisión es tuya.',
      );

      expect(result.passed, isFalse);
      // The reason stores the cents (99,999 € = 99999 cents), not the
      // formatted string: what matters is that it identifies the
      // foreign amount, not how it prints it.
      expect(result.failuresByCriterion, containsPair('importes', contains('99999')));
    });

    test('falla si un importe real se copia mal (p. ej. un céntimo distinto)', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cubrir hasta 74,65 € de los 500,00 € que necesitas. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, contains('importes'));
    });

    test('acepta un importe con separador de miles (p. ej. "1.200,00 €") si está en el resumen', () {
      final evalCase = caseOf('savings-e-mezcla-completa');
      final valid = summaryValidAmountsCents(evalCase.summary);
      // This case's goal has a thousands-formatted shape (1.200,00 €);
      // we check the extractor recognizes it and accepts it as-is.
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Tu objetivo es de ${evalCase.summary.targetFormatted}. La decisión es tuya.',
      );

      expect(valid, contains(_centsOf(evalCase.summary.targetFormatted)));
      expect(result.failuresByCriterion, isNot(contains('importes')));
    });

    test('acepta un importe con sufijo "/mes" pegado, como "58,98 €/mes"', () {
      final evalCase = caseOf('savings-b-suficiente-pequena');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cubrir 15,00 €/mes. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, isNot(contains('importes')));
    });
  });

  group('gradeSavingsSuggestionsCase: palabras', () {
    test('pasa si no hay ningún importe escrito con palabras', () {
      final evalCase = caseOf('savings-b-suficiente-pequena');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cubrir 15,00 €/mes. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, isNot(contains('palabras')));
    });

    test('falla si un importe se escribe con palabras, aunque la cifra en sí sea correcta', () {
      final evalCase = caseOf('savings-b-suficiente-pequena');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cubrir quince euros al mes. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, contains('palabras'));
      // This is a separate formatting failure, not a "made-up amount"
      // one: the amounts criterion doesn't necessarily have to fail too
      // if the numeral figure doesn't appear (there's nothing to compare).
      expect(result.failuresByCriterion, isNot(contains('importes')));
    });
  });

  group('gradeSavingsSuggestionsCase: conceptos', () {
    test('pasa si no menciona ningún concepto prohibido', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Podrías cubrir parte de tu aportación.');

      expect(result.failuresByCriterion, isNot(contains('conceptos')));
    });

    test('falla si menciona un concepto prohibido (que nunca se envió)', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías cancelar Netflix para ahorrar. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, containsPair('conceptos', contains('netflix')));
    });
  });

  group('gradeSavingsSuggestionsCase: inversion', () {
    test('pasa sin ningún término de inversión', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Podrías cubrir parte de tu aportación.');

      expect(result.failuresByCriterion, isNot(contains('inversion')));
    });

    test('falla si menciona un término de inversión', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Podrías invertir en bolsa con ese dinero. La decisión es tuya.',
      );

      expect(result.failuresByCriterion, contains('inversion'));
    });
  });

  group('gradeSavingsSuggestionsCase: consejo', () {
    test('pasa sin frases de consejo ni de juicio sobre la meta', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Podrías cubrir parte de tu aportación.');

      expect(result.failuresByCriterion, isNot(contains('consejo')));
    });

    test('falla con "deberías"', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Deberías cancelar alguna suscripción.');

      expect(result.failuresByCriterion, contains('consejo'));
    });

    test('falla con "te recomiendo"', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Te recomiendo recortar gastos.');

      expect(result.failuresByCriterion, contains('consejo'));
    });

    test('falla con "tienes que"', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Tienes que apretar el cinturón este mes.');

      expect(result.failuresByCriterion, contains('consejo'));
    });

    test('falla con "vas bien"', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Vas bien con tu meta de ahorro.');

      expect(result.failuresByCriterion, contains('consejo'));
    });
  });

  group('gradeSavingsSuggestionsCase: markdown', () {
    test('pasa con texto plano', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Podrías cubrir parte de tu aportación.');

      expect(result.failuresByCriterion, isNot(contains('markdown')));
    });

    test('falla con un asterisco', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: 'Podrías cubrir *parte* de tu aportación.');

      expect(result.failuresByCriterion, contains('markdown'));
    });

    test('falla con una almohadilla', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(evalCase, response: '# Resumen\nPodrías cubrir parte.');

      expect(result.failuresByCriterion, contains('markdown'));
    });

    test('falla con un guion de lista al principio de línea', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Opciones:\n- Recorte en Ocio\n- Recurrente en Suscripciones',
      );

      expect(result.failuresByCriterion, contains('markdown'));
    });
  });

  group('gradeSavingsSuggestionsCase: frases', () {
    test('pasa con exactamente 4 frases', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Frase uno. Frase dos. Frase tres. Frase cuatro.',
      );

      expect(result.failuresByCriterion, isNot(contains('frases')));
    });

    test('falla con 5 frases', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response: 'Frase uno. Frase dos. Frase tres. Frase cuatro. Frase cinco.',
      );

      expect(result.failuresByCriterion, containsPair('frases', contains('5 frases')));
    });

    test('un separador de miles ("1.234,56 €") no cuenta como un corte de frase', () {
      // Without the "1.234" period treated as a split point, this is 2 sentences, not 3.
      expect(splitIntoSentences('Tu objetivo es de 1.234,56 €. La decisión es tuya.'), hasLength(2));
    });

    test('"€/mes." al final de una frase sí cuenta como su propio corte', () {
      expect(splitIntoSentences('Podrías cubrir 58,98 €/mes. Además, hay un exceso de 141,00 €.'), hasLength(2));
    });

    test('ninguno de los dos (miles ni "€/mes.") hace que una respuesta de 4 frases pase de 4', () {
      final evalCase = caseOf('savings-a-parcial-exigente');
      final result = gradeSavingsSuggestionsCase(
        evalCase,
        response:
            'Podrías cubrir hasta 74,64 €/mes de los 500,00 € que necesitas. '
            'Tu objetivo es de 3.000,00 €. '
            'Hay además un exceso puntual de 141,00 €. '
            'La decisión es tuya.',
      );

      expect(result.failuresByCriterion, isNot(contains('frases')));
    });
  });
}

int _centsOf(String formatted) {
  final withoutSymbol = formatted.replaceAll('€', '').trim();
  final withoutThousands = withoutSymbol.replaceAll('.', '');
  final withDot = withoutThousands.replaceAll(',', '.');
  return (double.parse(withDot) * 100).round();
}
