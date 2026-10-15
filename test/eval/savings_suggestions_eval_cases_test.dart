import 'package:accounting_saver/eval/savings_suggestions_eval_cases.dart';
import 'package:accounting_saver/eval/savings_suggestions_eval_grading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSavingsSuggestionsEvalCases', () {
    final cases = buildSavingsSuggestionsEvalCases();

    test('hay exactamente los 5 casos pedidos, con ids únicos', () {
      expect(cases, hasLength(5));
      expect(cases.map((c) => c.id).toSet(), hasLength(5));
    });

    test('(a) meta exigente: cobertura parcial, con exceso puntual', () {
      final evalCase = cases.firstWhere((c) => c.id == 'savings-a-parcial-exigente');

      expect(evalCase.summary.targetFormatted, '3.000,00 €');
      expect(evalCase.summary.monthlyContributionFormatted, '500,00 €');
      expect(evalCase.summary.monthlyCoveredFormatted, '74,64 €');
      expect(evalCase.summary.oneOffExcesses.single.amountFormatted, '141,00 €');
    });

    test('(b) meta pequeña: cobertura suficiente, sin exceso puntual', () {
      final evalCase = cases.firstWhere((c) => c.id == 'savings-b-suficiente-pequena');

      expect(evalCase.summary.monthlyContributionFormatted, '9,10 €');
      expect(evalCase.summary.monthlyCoveredFormatted, '15,00 €');
      expect(evalCase.summary.oneOffExcesses, isEmpty);
    });

    test('(c) cobertura cero: ninguna lista de opciones tiene nada', () {
      final evalCase = cases.firstWhere((c) => c.id == 'savings-c-sin-opciones');

      expect(evalCase.summary.recurringByCategory, isEmpty);
      expect(evalCase.summary.categoryCuts, isEmpty);
      expect(evalCase.summary.oneOffExcesses, isEmpty);
      expect(evalCase.summary.monthlyCoveredFormatted, '0,00 €');
    });

    test('(d) sin exceso puntual, pero con recurrente y recorte', () {
      final evalCase = cases.firstWhere((c) => c.id == 'savings-d-sin-exceso-puntual');

      expect(evalCase.summary.recurringByCategory, isNotEmpty);
      expect(evalCase.summary.categoryCuts, isNotEmpty);
      expect(evalCase.summary.oneOffExcesses, isEmpty);
    });

    test('(e) recurrentes, recortes y exceso puntual a la vez', () {
      final evalCase = cases.firstWhere((c) => c.id == 'savings-e-mezcla-completa');

      expect(evalCase.summary.recurringByCategory, isNotEmpty);
      expect(evalCase.summary.categoryCuts, isNotEmpty);
      expect(evalCase.summary.oneOffExcesses, isNotEmpty);
    });

    test(
      'ningún resumen contiene los conceptos fabricados ("netflix", "spotify", "gimnasio"), '
      'aunque se usaron como descripción al fabricar los casos',
      () {
        for (final evalCase in cases) {
          final summary = evalCase.summary;
          final allText = [
            summary.targetFormatted,
            summary.savedFormatted,
            summary.monthlyContributionFormatted,
            summary.monthlyCoveredFormatted,
            summary.coverageLine,
            for (final item in summary.recurringByCategory) item.line,
            for (final item in summary.categoryCuts) item.line,
            for (final item in summary.oneOffExcesses) item.line,
          ].join(' ').toLowerCase();

          for (final concept in savingsSuggestionsForbiddenConcepts) {
            expect(
              allText,
              isNot(contains(concept)),
              reason: 'el caso ${evalCase.id} no debería transportar "$concept" en ningún campo',
            );
          }
        }
      },
    );
  });
}
