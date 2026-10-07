import 'package:accounting_saver/application/transactions/parse_natural_language_transaction.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/domain/transactions/not_understood_exception.dart';
import 'package:accounting_saver/domain/transactions/raw_parsed_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_llm_gateway.dart';

final _today = DateTime(2026, 10, 7);

RawParsedTransaction _rawTransaction({
  int amountCents = -1250,
  DateTime? date,
  String description = 'Bar con Marta',
  String categoryName = 'restaurantes',
}) {
  return RawParsedTransaction(
    understood: true,
    amountCents: amountCents,
    date: date ?? _today,
    description: description,
    categoryName: categoryName,
  );
}

void main() {
  group('ParseNaturalLanguageTransaction', () {
    test('devuelve una propuesta válida a partir del resultado del gateway', () async {
      final gateway = FakeLlmGateway.returning(_rawTransaction());
      final useCase = ParseNaturalLanguageTransaction(gateway);

      final result = await useCase(text: '12,50 en el bar con Marta', now: _today);

      expect(result.amountCents, -1250);
      expect(result.date, _today);
      expect(result.description, 'Bar con Marta');
      expect(result.categoryId, Category.restaurantes);
      expect(gateway.lastText, '12,50 en el bar con Marta');
      expect(gateway.lastNow, _today);
    });

    test('acepta un importe escrito con palabras ("doce euros en el bar")', () async {
      final gateway = FakeLlmGateway.returning(
        _rawTransaction(amountCents: -1200, description: 'Bar'),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      final result = await useCase(text: 'doce euros en el bar', now: _today);

      expect(result.amountCents, -1200);
    });

    test('rechaza un texto sin ningún número ("asdf") aunque el gateway diga que no entiende', () async {
      final gateway = FakeLlmGateway.returning(
        const RawParsedTransaction(understood: false),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: 'asdf', now: _today),
        throwsA(isA<NotUnderstoodException>()),
      );
    });

    test(
      'rechaza por el contraste un texto sin dígitos aunque el gateway devuelva un importe',
      () async {
        final gateway = FakeLlmGateway.returning(_rawTransaction(amountCents: 1));
        final useCase = ParseNaturalLanguageTransaction(gateway);

        await expectLater(
          useCase(text: 'hola que tal', now: _today),
          throwsA(isA<NotUnderstoodException>()),
        );
      },
    );

    test('rechaza "hola"', () async {
      final gateway = FakeLlmGateway.returning(_rawTransaction());
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: 'hola', now: _today),
        throwsA(isA<NotUnderstoodException>()),
      );
    });

    test('rechaza un texto vacío', () async {
      final gateway = FakeLlmGateway.returning(_rawTransaction());
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '', now: _today),
        throwsA(isA<NotUnderstoodException>()),
      );
    });

    test('rechaza "bar ayer" por no mencionar ningún importe', () async {
      final gateway = FakeLlmGateway.returning(_rawTransaction());
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: 'bar ayer', now: _today),
        throwsA(isA<NotUnderstoodException>()),
      );
    });

    test('rechaza cuando el gateway entiende pero falta algún campo', () async {
      final gateway = FakeLlmGateway.returning(
        const RawParsedTransaction(understood: true, amountCents: 500),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '5 euros en algo', now: _today),
        throwsA(isA<NotUnderstoodException>()),
      );
    });

    test('rechaza una categoría que no existe en el enum', () async {
      final gateway = FakeLlmGateway.returning(
        _rawTransaction(categoryName: 'no-existe'),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '12 euros en algo', now: _today),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rechaza un importe por encima del límite', () async {
      final gateway = FakeLlmGateway.returning(
        _rawTransaction(amountCents: -100000001),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: 'un gasto de 100000001 céntimos', now: _today),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propaga una respuesta malformada como LlmGatewayException', () async {
      final gateway = FakeLlmGateway.throwing(
        const LlmGatewayException('malformed-response'),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '12 euros en algo ininteligible', now: _today),
        throwsA(
          isA<LlmGatewayException>().having((e) => e.code, 'code', 'malformed-response'),
        ),
      );
    });

    test('propaga un error de cuota como LlmGatewayException', () async {
      final gateway = FakeLlmGateway.throwing(
        const LlmGatewayException('quota-exceeded'),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: 'un café de 2 euros', now: _today),
        throwsA(
          isA<LlmGatewayException>().having((e) => e.code, 'code', 'quota-exceeded'),
        ),
      );
    });

    test('rechaza una fecha futura poco razonable', () async {
      final gateway = FakeLlmGateway.returning(
        _rawTransaction(date: _today.add(const Duration(days: 10))),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '12 euros el mes que viene', now: _today),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rechaza una fecha demasiado antigua', () async {
      final gateway = FakeLlmGateway.returning(
        _rawTransaction(date: DateTime(2015, 1, 1)),
      );
      final useCase = ParseNaturalLanguageTransaction(gateway);

      await expectLater(
        useCase(text: '12 euros hace mucho', now: _today),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
