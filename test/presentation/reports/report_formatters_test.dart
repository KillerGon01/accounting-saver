import 'package:accounting_saver/presentation/reports/report_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPercentage', () {
    test('redondea a un decimal, con coma', () {
      expect(formatPercentage(100 / 3), '33,3 %');
    });

    test('no muestra más de un decimal aunque el valor sea exacto', () {
      expect(formatPercentage(50), '50,0 %');
    });

    test('un valor que redondea hacia arriba', () {
      expect(formatPercentage(33.36), '33,4 %');
    });

    test('acepta valores negativos (deltas de comparación)', () {
      expect(formatPercentage(-12.34), '-12,3 %');
    });
  });
}
