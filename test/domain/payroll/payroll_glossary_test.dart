import 'package:accounting_saver/domain/payroll/payroll_glossary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un concepto conocido devuelve su descripción', () {
    expect(
      payrollGlossaryDescription('Contingencias comunes'),
      isNot(payrollGlossaryUnknownDescription),
    );
    expect(payrollGlossaryDescription('IRPF'), isNot(payrollGlossaryUnknownDescription));
  });

  test('IRPF y MEI tienen una descripción en lenguaje sencillo, sin tipos concretos', () {
    expect(
      payrollGlossaryDescription('IRPF'),
      allOf(contains('Hacienda'), contains('porcentaje depende de tus circunstancias')),
    );
    expect(
      payrollGlossaryDescription('Mecanismo de Equidad Intergeneracional'),
      allOf(contains('sistema de pensiones'), contains('varía según el año')),
    );
    expect(
      payrollGlossaryDescription('MEI'),
      payrollGlossaryDescription('Mecanismo de Equidad Intergeneracional'),
    );
    // Sin tipos de cotización concretos: ningún número de porcentaje en el texto.
    expect(payrollGlossaryDescription('IRPF'), isNot(contains(RegExp(r'\d'))));
    expect(payrollGlossaryDescription('MEI'), isNot(contains(RegExp(r'\d'))));
  });

  test('un concepto desconocido devuelve el texto "sin descripción"', () {
    expect(payrollGlossaryDescription('Plan de pensiones de empresa'), payrollGlossaryUnknownDescription);
  });

  test('normaliza mayúsculas y acentos al buscar', () {
    final base = payrollGlossaryDescription('mecanismo de equidad intergeneracional');
    expect(payrollGlossaryDescription('MECANISMO DE EQUIDAD INTERGENERACIONAL'), base);
    expect(payrollGlossaryDescription('Mecanismo De Equidad Intergeneracional'), base);
    expect(payrollGlossaryDescription('mei'), isNot(payrollGlossaryUnknownDescription));
    expect(payrollGlossaryDescription('MEI'), payrollGlossaryDescription('mei'));
    expect(payrollGlossaryDescription('Formación profesional'), payrollGlossaryDescription('formacion profesional'));
  });
}
