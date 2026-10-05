import 'package:accounting_saver/domain/transactions/amount_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEurosToCents', () {
    test('acepta coma y punto como separador decimal', () {
      expect(parseEurosToCents('12,50'), 1250);
      expect(parseEurosToCents('12.50'), 1250);
    });

    test('acepta importes sin decimales o con un solo decimal', () {
      expect(parseEurosToCents('12'), 1200);
      expect(parseEurosToCents('12,5'), 1250);
      expect(parseEurosToCents('0,05'), 5);
    });

    test('ignora espacios alrededor', () {
      expect(parseEurosToCents('  7,00 '), 700);
    });

    test('devuelve cero para importes nulos (la validación lo rechaza)', () {
      expect(parseEurosToCents('0'), 0);
      expect(parseEurosToCents('0,00'), 0);
    });

    test('rechaza formatos no válidos', () {
      expect(parseEurosToCents(''), isNull);
      expect(parseEurosToCents('abc'), isNull);
      expect(parseEurosToCents('-5'), isNull);
      expect(parseEurosToCents('1,234'), isNull);
      expect(parseEurosToCents('1,2,3'), isNull);
      expect(parseEurosToCents('1.234,56'), isNull);
    });

    test('rechaza importes desbordados', () {
      expect(parseEurosToCents('1000000000'), isNull);
    });
  });
}
