import 'package:accounting_saver/domain/payroll/payroll_glossary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los 5 conceptos literales que devuelve el modelo en las fixtures de la
/// prueba de viabilidad (ver docs/evaluation.md): los dos últimos llevan
/// un paréntesis explicativo o la sigla entre paréntesis, que es justo lo
/// que rompía la igualdad exacta de antes.
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
    // Sin tipos de cotización concretos: ningún número de porcentaje en el texto.
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

    // Variantes con el paréntesis, mayúsculas distintas, acentos y espacios
    // de más (incluidos dobles espacios y espacios alrededor del
    // paréntesis) — el mismo texto que acompaña, normalizado, no debería
    // cambiar la descripción encontrada.
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
    // "mei" es una subcadena literal de "premeido", pero no una palabra o
    // sigla completa (sin límite de palabra a ningún lado): no debe
    // coincidir con la entrada "mei" del glosario.
    expect(payrollGlossaryDescription('Premeido'), payrollGlossaryUnknownDescription);
    // Mismo caso con "irpf" incrustado en otra palabra sin límites.
    expect(payrollGlossaryDescription('Birpfusion'), payrollGlossaryUnknownDescription);
  });
}
