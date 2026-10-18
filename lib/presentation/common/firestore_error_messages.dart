import 'package:cloud_firestore/cloud_firestore.dart';

/// Doesn't claim the problem is an unverified email: a
/// `permission-denied` can also come from another cause (rules, a
/// revoked token...). It only gives the most likely hint, without
/// promising it.
const _permissionDeniedMessage =
    'No tienes permiso para ver estos datos. Si acabas de verificar tu correo, cierra sesión y vuelve a entrar.';

/// `true` if [error] is the `FirebaseException` Firestore throws when
/// the security rules deny the operation (code
/// `'permission-denied'`), regardless of which rule it was.
bool isFirestorePermissionDenied(Object error) {
  return error is FirebaseException && error.code == 'permission-denied';
}

/// Spanish-language message for an error reading from or writing to
/// Firestore. Never the raw error: [fallback] is the text for any
/// other case (network, service unavailable...), specific to each
/// screen.
String firestoreErrorMessage(Object error, {required String fallback}) {
  if (isFirestorePermissionDenied(error)) return _permissionDeniedMessage;
  return fallback;
}
