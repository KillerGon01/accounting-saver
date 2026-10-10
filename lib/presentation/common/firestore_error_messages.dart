import 'package:cloud_firestore/cloud_firestore.dart';

/// No afirma que el problema sea el correo sin verificar: un
/// `permission-denied` también puede venir de otra causa (reglas, un
/// token revocado...). Solo da la pista más probable, sin prometerla.
const _permissionDeniedMessage =
    'No tienes permiso para ver estos datos. Si acabas de verificar tu correo, cierra sesión y vuelve a entrar.';

/// `true` si [error] es el `FirebaseException` que Firestore lanza cuando
/// las reglas de seguridad deniegan la operación (código
/// `'permission-denied'`), sin importar qué regla ha sido.
bool isFirestorePermissionDenied(Object error) {
  return error is FirebaseException && error.code == 'permission-denied';
}

/// Mensaje en español para un error al leer o escribir en Firestore.
/// Nunca el error crudo: [fallback] es el texto para cualquier otro caso
/// (red, servicio no disponible...), específico de cada pantalla.
String firestoreErrorMessage(Object error, {required String fallback}) {
  if (isFirestorePermissionDenied(error)) return _permissionDeniedMessage;
  return fallback;
}
