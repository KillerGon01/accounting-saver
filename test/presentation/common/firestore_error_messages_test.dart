import 'package:accounting_saver/presentation/common/firestore_error_messages.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isFirestorePermissionDenied', () {
    test('un FirebaseException con code permission-denied lo es', () {
      final error = FirebaseException(plugin: 'firestore', code: 'permission-denied');
      expect(isFirestorePermissionDenied(error), isTrue);
    });

    test('un FirebaseException con otro código no lo es', () {
      final error = FirebaseException(plugin: 'firestore', code: 'unavailable');
      expect(isFirestorePermissionDenied(error), isFalse);
    });

    test('un error que no es de Firestore no lo es', () {
      expect(isFirestorePermissionDenied(StateError('otra cosa')), isFalse);
    });
  });

  group('firestoreErrorMessage', () {
    test('permission-denied: mensaje de permiso, sin afirmar que sea el correo', () {
      final error = FirebaseException(plugin: 'firestore', code: 'permission-denied');

      final message = firestoreErrorMessage(error, fallback: 'genérico');

      expect(
        message,
        'No tienes permiso para ver estos datos. Si acabas de verificar tu correo, cierra sesión y vuelve a entrar.',
      );
      expect(message, isNot(contains('[firestore/')));
    });

    test('nunca el error crudo, ni para permission-denied ni para el resto', () {
      final error = FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

      final message = firestoreErrorMessage(error, fallback: 'genérico');

      expect(message, isNot(contains('Missing or insufficient permissions')));
    });

    test('cualquier otro error devuelve el fallback de la pantalla, no el crudo', () {
      final error = FirebaseException(plugin: 'firestore', code: 'unavailable', message: 'network down');

      final message = firestoreErrorMessage(
        error,
        fallback: 'No se pudieron cargar los movimientos. Inténtalo de nuevo más tarde.',
      );

      expect(message, 'No se pudieron cargar los movimientos. Inténtalo de nuevo más tarde.');
      expect(message, isNot(contains('network down')));
    });

    test('un error que no es de Firestore también devuelve el fallback', () {
      final message = firestoreErrorMessage(StateError('boom'), fallback: 'genérico');
      expect(message, 'genérico');
    });
  });
}
