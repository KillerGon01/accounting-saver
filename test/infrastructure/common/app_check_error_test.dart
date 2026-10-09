import 'package:accounting_saver/infrastructure/common/app_check_error.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAppCheckAttestationError', () {
    test('un 403 con "App attestation failed" es un fallo de App Check', () {
      expect(
        isAppCheckAttestationError(
          FirebaseAIException('Permission denied: App attestation failed.'),
        ),
        isTrue,
      );
    });

    test('un error con status PERMISSION_DENIED es un fallo de App Check', () {
      expect(
        isAppCheckAttestationError(FirebaseAIException('PERMISSION_DENIED: no autorizado')),
        isTrue,
      );
    });

    test('la cuota agotada no es un fallo de App Check (lo gestiona el fallback de modelo)', () {
      expect(isAppCheckAttestationError(QuotaExceeded('Quota exceeded')), isFalse);
    });

    test('un fallo transitorio del servidor no es un fallo de App Check', () {
      expect(
        isAppCheckAttestationError(FirebaseAIException('Server Error [503]: UNAVAILABLE')),
        isFalse,
      );
    });

    test('otro FirebaseAIException sin esos textos no es un fallo de App Check', () {
      expect(isAppCheckAttestationError(InvalidApiKey('clave inválida')), isFalse);
    });

    test('un error que no es de firebase_ai no es un fallo de App Check', () {
      expect(isAppCheckAttestationError(StateError('otra cosa')), isFalse);
    });
  });
}
