import 'package:accounting_saver/domain/transactions/number_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('textContainsNumber', () {
    test('detecta dígitos', () {
      expect(textContainsNumber('12,50 en el bar'), isTrue);
    });

    test('detecta palabras de número en español', () {
      expect(textContainsNumber('doce euros en el bar'), isTrue);
      expect(textContainsNumber('treinta euros de gasolina'), isTrue);
      expect(textContainsNumber('cien euros de alquiler'), isTrue);
      expect(textContainsNumber('mil euros de nómina'), isTrue);
    });

    test('ignora mayúsculas y acentos', () {
      expect(textContainsNumber('DIECISÉIS euros'), isTrue);
    });

    test('no detecta nada en texto sin números', () {
      expect(textContainsNumber('asdf'), isFalse);
      expect(textContainsNumber('hola'), isFalse);
      expect(textContainsNumber(''), isFalse);
      expect(textContainsNumber('bar ayer'), isFalse);
    });
  });
}
