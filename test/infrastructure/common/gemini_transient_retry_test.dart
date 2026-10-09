import 'package:accounting_saver/infrastructure/common/gemini_model_fallback.dart';
import 'package:accounting_saver/infrastructure/common/gemini_transient_retry.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';

void main() {
  group('isTransientGeminiError', () {
    test('un 503 ("Server Error [503]: ...") es transitorio', () {
      expect(
        isTransientGeminiError(FirebaseAIException('Server Error [503]: {"error":{"code":503}}')),
        isTrue,
      );
    });

    test('un error con status UNAVAILABLE es transitorio', () {
      expect(isTransientGeminiError(FirebaseAIException('UNAVAILABLE: servicio ocupado')), isTrue);
    });

    test('un "Deadline expired" es transitorio', () {
      expect(
        isTransientGeminiError(FirebaseAIException('Deadline expired before operation could complete.')),
        isTrue,
      );
    });

    test('la cuota agotada no es un error transitorio (lo gestiona el fallback de modelo)', () {
      expect(isTransientGeminiError(QuotaExceeded('Quota exceeded')), isFalse);
    });

    test('otro FirebaseAIException sin esos textos no es transitorio', () {
      expect(isTransientGeminiError(InvalidApiKey('clave inválida')), isFalse);
    });

    test('un error que no es de firebase_ai no es transitorio', () {
      expect(isTransientGeminiError(StateError('otra cosa')), isFalse);
    });
  });

  group('withTransientRetry', () {
    test('devuelve el resultado directamente si no hay error', () async {
      final result = await withTransientRetry(() async => 'ok', delay: Duration.zero);
      expect(result, 'ok');
    });

    test('reintenta una vez tras un 503 y devuelve el resultado si el reintento funciona', () async {
      var attempts = 0;

      final result = await withTransientRetry(() async {
        attempts++;
        if (attempts == 1) throw FirebaseAIException('Server Error [503]: UNAVAILABLE');
        return 'ok tras reintentar';
      }, delay: Duration.zero);

      expect(result, 'ok tras reintentar');
      expect(attempts, 2);
    });

    test('si los dos intentos fallan por 503, relanza el error sin un tercer intento', () async {
      var attempts = 0;

      await expectLater(
        withTransientRetry(() async {
          attempts++;
          throw FirebaseAIException('Server Error [503]: UNAVAILABLE');
        }, delay: Duration.zero),
        throwsA(isA<FirebaseAIException>()),
      );

      expect(attempts, 2);
    });

    test('no reintenta ante un error que no es transitorio', () async {
      var attempts = 0;

      await expectLater(
        withTransientRetry(() async {
          attempts++;
          throw QuotaExceeded('Quota exceeded');
        }, delay: Duration.zero),
        throwsA(isA<QuotaExceeded>()),
      );

      expect(attempts, 1);
    });

    test('un 503 no marca ningún modelo como agotado al combinarse con el fallback', () async {
      final availability = GeminiModelAvailability(clock: FakeClock(DateTime(2026, 10, 9)));
      var attempts = 0;

      final result = await withGeminiModelFallback(
        availability: availability,
        models: const ['gemini-3.8-flash', 'gemini-2.5-flash'],
        attempt: (model) => withTransientRetry(() async {
          attempts++;
          if (attempts == 1) throw FirebaseAIException('Server Error [503]: UNAVAILABLE');
          return 'ok';
        }, delay: Duration.zero),
      );

      expect(result, 'ok');
      // El reintento ocurrió con el mismo modelo (gemini-3.8-flash): el
      // fallback de modelo nunca llegó a intervenir.
      expect(attempts, 2);
      expect(availability.isAvailable('gemini-3.8-flash'), isTrue);
      expect(availability.isAvailable('gemini-2.5-flash'), isTrue);
    });
  });
}
