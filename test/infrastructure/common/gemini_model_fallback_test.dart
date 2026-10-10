import 'dart:async';

import 'package:accounting_saver/domain/common/clock.dart';
import 'package:accounting_saver/infrastructure/common/gemini_model_fallback.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';

/// Reloj mutable para simular el paso del tiempo en un mismo
/// [GeminiModelAvailability], algo que [FakeClock] (fijo) no permite.
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
