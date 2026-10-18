import 'dart:async';

import 'package:accounting_saver/domain/common/clock.dart';
import 'package:accounting_saver/infrastructure/common/gemini_model_fallback.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';

/// Mutable clock for simulating the passage of time within a single
/// [GeminiModelAvailability], something [FakeClock] (fixed) doesn't allow.
class _MutableClock implements Clock {
  _MutableClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  group('GeminiModelAvailability', () {
    test('un modelo nunca marcado está disponible', () {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));

      expect(availability.isAvailable('gemini-3.8-flash'), isTrue);
    });

    test('un modelo marcado como agotado deja de estar disponible', () {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9, 12)));

      availability.markExhausted('gemini-3.8-flash');

      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);
    });

    test('vuelve a estar disponible una hora después de agotarse', () {
      final clock = _MutableClock(DateTime(2026, 10, 9, 12));
      final availability = GeminiModelAvailability(clock: clock);

      availability.markExhausted('gemini-3.8-flash');
      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);

      clock.advance(const Duration(minutes: 59));
      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);

      clock.advance(const Duration(minutes: 2));
      expect(availability.isAvailable('gemini-3.8-flash'), isTrue);
    });

    test('un modelo marcado como no disponible para la sesión no vuelve a estar disponible', () {
      final clock = _MutableClock(DateTime(2026, 10, 9, 12));
      final availability = GeminiModelAvailability(clock: clock);

      availability.markUnavailableForSession('gemini-2.5-flash');
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);

      // Unlike `markExhausted`, it doesn't expire over time: an hour,
      // a day, whatever, it stays unavailable.
      clock.advance(const Duration(days: 1));
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);
    });
  });

  group('isModelNotFoundError', () {
    test('un 404 "is not found for API version..." lo es', () {
      final error = ServerException(
        'models/gemini-2.5-flash is not found for API version v1beta, or is not '
        'supported for generateContent. Call ListModels to see the list of available '
        'models and their supported methods.',
      );
      expect(isModelNotFoundError(error), isTrue);
    });

    test('un 404 "no longer available to new users..." también lo es', () {
      // Real message returned by Gemini for a model retired for new
      // projects (gemini-2.5-flash-lite), before the API retires it
      // completely with the other message above. `ServerException`
      // doesn't expose the HTTP code (404) or the "status" ("NOT_FOUND")
      // of the error body (see the comment on `isModelNotFoundError`),
      // only this text.
      final error = ServerException(
        'This model models/gemini-2.5-flash-lite is no longer available to new users. '
        'Please update your code to use models/gemini-3.5-flash-lite before you make '
        'additional requests to the Gemini API.',
      );
      expect(isModelNotFoundError(error), isTrue);
    });

    test('la cuota agotada no lo es (lo gestiona el fallback de cuota)', () {
      expect(isModelNotFoundError(QuotaExceeded('Quota exceeded')), isFalse);
    });

    test('otro FirebaseAIException sin ese texto no lo es', () {
      expect(isModelNotFoundError(InvalidApiKey('clave inválida')), isFalse);
    });

    test('un error que no es de firebase_ai no lo es', () {
      expect(isModelNotFoundError(StateError('otra cosa')), isFalse);
    });
  });

  group('withGeminiModelFallback', () {
    test('usa el primer modelo si responde bien', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
        attempt: (model) async {
          tried.add(model);
          return 'respuesta de $model';
        },
      );

      expect(result, 'respuesta de gemini-3.8-flash');
      expect(tried, ['gemini-3.8-flash']);
    });

    test('reintenta una vez con el siguiente modelo tras un 429', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
        attempt: (model) async {
          tried.add(model);
          if (model == 'gemini-3.8-flash') throw QuotaExceeded('Quota exceeded');
          return 'respuesta de $model';
        },
      );

      expect(result, 'respuesta de gemini-2.5-flash');
      expect(tried, ['gemini-3.8-flash', 'gemini-2.5-flash']);
      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);
    });

    test('no reintenta un modelo ya marcado como agotado', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      availability.markExhausted('gemini-3.8-flash');
      final tried = <String>[];

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
        attempt: (model) async {
          tried.add(model);
          return 'respuesta de $model';
        },
      );

      expect(result, 'respuesta de gemini-2.5-flash');
      expect(tried, ['gemini-2.5-flash']);
    });

    test('lanza QuotaExceeded si todos los modelos fallan', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      await expectLater(
        withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
          attempt: (model) async {
            tried.add(model);
            throw QuotaExceeded('Quota exceeded');
          },
        ),
        throwsA(isA<QuotaExceeded>()),
      );
      expect(tried, ['gemini-3.8-flash', 'gemini-2.5-flash']);
      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);
    });

    test('lanza QuotaExceeded sin gastar ningún intento si todos los modelos ya están agotados', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      availability.markExhausted('gemini-3.8-flash');
      availability.markExhausted('gemini-2.5-flash');
      final tried = <String>[];

      await expectLater(
        withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
          attempt: (model) async {
            tried.add(model);
            return 'no debería llegar aquí';
          },
        ),
        throwsA(isA<QuotaExceeded>()),
      );
      expect(tried, isEmpty);
    });

    test('no reintenta con otro modelo ante un timeout, ni marca el modelo como agotado', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      await expectLater(
        withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
          attempt: (model) async {
            tried.add(model);
            throw TimeoutException('tardó demasiado');
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(tried, ['gemini-3.8-flash']);
      expect(availability.isAvailable('gemini-3.8-flash'), isTrue);
    });

    test('404 en el primer modelo: pasa al siguiente y responde bien', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
        attempt: (model) async {
          tried.add(model);
          if (model == 'gemini-2.5-flash') {
            throw ServerException(
              'models/gemini-2.5-flash is not found for API version v1beta, or is not '
              'supported for generateContent.',
            );
          }
          return 'respuesta de $model';
        },
      );

      expect(result, 'respuesta de gemini-2.5-flash-lite');
      expect(tried, ['gemini-2.5-flash', 'gemini-2.5-flash-lite']);
      // Marked for the whole session (not 1 hour like `markExhausted`):
      // there's no date to "become available again".
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);
      expect(availability.isAvailable('gemini-2.5-flash-lite'), isTrue);
    });

    test('404 en todos los modelos: relanza el error del último, todos quedan marcados', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      await expectLater(
        withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
          attempt: (model) async {
            tried.add(model);
            throw ServerException('models/$model is not found for API version v1beta.');
          },
        ),
        throwsA(isA<ServerException>()),
      );

      expect(tried, ['gemini-2.5-flash', 'gemini-2.5-flash-lite']);
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);
      expect(availability.isAvailable('gemini-2.5-flash-lite'), isFalse);
    });

    test('429 en el primero y 404 en el segundo: cada causa queda marcada con su propio mecanismo', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-3.8-flash', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'],
        attempt: (model) async {
          tried.add(model);
          switch (model) {
            case 'gemini-3.8-flash':
              throw QuotaExceeded('Quota exceeded');
            case 'gemini-2.5-flash':
              throw ServerException(
                'models/gemini-2.5-flash is not found for API version v1beta.',
              );
            default:
              return 'respuesta de $model';
          }
        },
      );

      expect(result, 'respuesta de gemini-2.5-flash-lite');
      expect(tried, ['gemini-3.8-flash', 'gemini-2.5-flash', 'gemini-2.5-flash-lite']);
      expect(availability.isAvailable('gemini-3.8-flash'), isFalse);
      expect(availability.isAvailable('gemini-2.5-flash'), isFalse);
      expect(availability.isAvailable('gemini-2.5-flash-lite'), isTrue);
    });

    test(
      '404 "no longer available to new users...": pasa al siguiente modelo y responde bien',
      () async {
        final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
        final tried = <String>[];

        final result = await withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite'],
          attempt: (model) async {
            tried.add(model);
            if (model == 'gemini-2.5-flash-lite') {
              throw ServerException(
                'This model models/gemini-2.5-flash-lite is no longer available to new '
                'users. Please update your code to use models/gemini-3.5-flash-lite.',
              );
            }
            return 'respuesta de $model';
          },
        );

        expect(result, 'respuesta de gemini-3.5-flash-lite');
        expect(tried, ['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite']);
        // Marked for the whole session, same as the other 404 message.
        expect(availability.isAvailable('gemini-2.5-flash-lite'), isFalse);
        expect(availability.isAvailable('gemini-3.5-flash-lite'), isTrue);
      },
    );

    test(
      'un modelo marcado por "no longer available..." no se vuelve a intentar en una llamada posterior',
      () async {
        final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
        final firstAttemptTried = <String>[];

        await withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite'],
          attempt: (model) async {
            firstAttemptTried.add(model);
            if (model == 'gemini-2.5-flash-lite') {
              throw ServerException(
                'This model models/gemini-2.5-flash-lite is no longer available to new '
                'users. Please update your code to use models/gemini-3.5-flash-lite.',
              );
            }
            return 'ok';
          },
        );
        expect(firstAttemptTried, ['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite']);

        // A new request with the same `availability`: the model marked
        // by this message shouldn't even be attempted.
        final secondAttemptTried = <String>[];
        final result = await withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite'],
          attempt: (model) async {
            secondAttemptTried.add(model);
            return 'respuesta de $model';
          },
        );

        expect(result, 'respuesta de gemini-3.5-flash-lite');
        expect(secondAttemptTried, ['gemini-3.5-flash-lite']);
      },
    );

    test('un modelo no disponible por 404 no se vuelve a intentar en una llamada posterior', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final firstAttemptTried = <String>[];

      await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
        attempt: (model) async {
          firstAttemptTried.add(model);
          if (model == 'gemini-2.5-flash') {
            throw ServerException(
              'models/gemini-2.5-flash is not found for API version v1beta.',
            );
          }
          return 'ok';
        },
      );
      expect(firstAttemptTried, ['gemini-2.5-flash', 'gemini-2.5-flash-lite']);

      // A new request (another question, another transaction...) with
      // the same `availability`: it shouldn't even try the marked model anymore.
      final secondAttemptTried = <String>[];
      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-2.5-flash', 'gemini-2.5-flash-lite'],
        attempt: (model) async {
          secondAttemptTried.add(model);
          return 'respuesta de $model';
        },
      );

      expect(result, 'respuesta de gemini-2.5-flash-lite');
      expect(secondAttemptTried, ['gemini-2.5-flash-lite']);
    });

    test('no reintenta ante un error que no es de cuota', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      final tried = <String>[];

      await expectLater(
        withGeminiModelFallback(
          availability: availability,
          models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
          attempt: (model) async {
            tried.add(model);
            throw InvalidApiKey('clave inválida');
          },
        ),
        throwsA(isA<InvalidApiKey>()),
      );
      expect(tried, ['gemini-3.8-flash']);
    });
  });
}
