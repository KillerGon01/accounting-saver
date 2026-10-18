import 'package:accounting_saver/domain/payroll/payroll_glossary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 5 literal concepts the model returns in the feasibility
/// spike's fixtures (see docs/evaluation.md): the last two carry an
/// explanatory parenthetical or the acronym in parentheses, which
/// is exactly what used to break the old exact equality.
const _knownConcepts = [
  'Contingencias comunes',
  'Desempleo',
  'Formación profesional',
  'Mecanismo de Equidad Intergeneracional (MEI)',
  'IRPF (retención a cuenta)',
];

void main() {
  test('los 5 conceptos literales del modelo tienen descripción', () {
    for (final concept in _knownConcepts) {
      expect(
        payrollGlossaryDescription(concept),
        isNot(payrollGlossaryUnknownDescription),
        reason: '"$concept" debería tener descripción',
      );
    }
  });

  test('IRPF y MEI tienen una descripción en lenguaje sencillo, sin tipos concretos', () {
    expect(
      payrollGlossaryDescription('IRPF (retención a cuenta)'),
      allOf(contains('Hacienda'), contains('porcentaje depende de tus circunstancias')),
    );
    expect(
      payrollGlossaryDescription('Mecanismo de Equidad Intergeneracional (MEI)'),
      allOf(contains('sistema de pensiones'), contains('varía según el año')),
    );
    // No specific contribution rates: no percentage number in the text.
    expect(payrollGlossaryDescription('IRPF (retención a cuenta)'), isNot(contains(RegExp(r'\d'))));
    expect(
      payrollGlossaryDescription('Mecanismo de Equidad Intergeneracional (MEI)'),
      isNot(contains(RegExp(r'\d'))),
    );
  });

  test('un concepto desconocido devuelve el texto "sin descripción"', () {
    expect(payrollGlossaryDescription('Plan de pensiones de empresa'), payrollGlossaryUnknownDescription);
  });

  test('normaliza mayúsculas, acentos y espacios de más al buscar', () {
    final base = payrollGlossaryDescription('mecanismo de equidad intergeneracional');
    expect(payrollGlossaryDescription('MECANISMO DE EQUIDAD INTERGENERACIONAL'), base);
    expect(payrollGlossaryDescription('Mecanismo De Equidad Intergeneracional'), base);
    expect(payrollGlossaryDescription('mei'), isNot(payrollGlossaryUnknownDescription));
    expect(payrollGlossaryDescription('MEI'), payrollGlossaryDescription('mei'));
    expect(payrollGlossaryDescription('Formación profesional'), payrollGlossaryDescription('formacion profesional'));

    // Variants with the parenthetical, different casing, accents,
    // and extra spaces (including double spaces and spaces around
    // the parenthesis) — the same accompanying text, normalized,
    // shouldn't change the description found.
    expect(
      payrollGlossaryDescription('  IRPF   (Retención a Cuenta)  '),
      payrollGlossaryDescription('irpf (retencion a cuenta)'),
    );
    expect(
      payrollGlossaryDescription('MECANISMO DE EQUIDAD INTERGENERACIONAL (mei)'),
      base,
    );
    expect(
      payrollGlossaryDescription('mecanismo  de  equidad  intergeneracional (MEI)'),
      base,
    );
  });

  test('no hay falso positivo cuando la sigla aparece como subcadena de otra palabra', () {
    // "mei" is a literal substring of "premeido", but not a whole
    // word or acronym (no word boundary on either side): it must
    // not match the glossary's "mei" entry.
    expect(payrollGlossaryDescription('Premeido'), payrollGlossaryUnknownDescription);
    // Same case with "irpf" embedded in another word with no boundaries.
    expect(payrollGlossaryDescription('Birpfusion'), payrollGlossaryUnknownDescription);
  });
}
