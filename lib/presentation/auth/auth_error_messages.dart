import '../../domain/auth/auth_exception.dart';
import 'auth_validators.dart';

const _genericMessage = 'No se pudo completar la operación. Inténtalo de nuevo.';

/// Spanish-language message for an authentication error. For wrong or
/// nonexistent credentials, the same text is used, so as not to
/// reveal whether the email has an account.
String authErrorMessage(Object error) {
  if (error is! AuthException) return _genericMessage;

  return switch (error.code) {
    'email-already-in-use' => 'Ya existe una cuenta con este correo electrónico.',
    'weak-password' =>
      'La contraseña es demasiado débil. Usa al menos $minPasswordLength caracteres.',
    'invalid-email' => 'El correo electrónico no tiene un formato válido.',
    'invalid-credential' || 'wrong-password' || 'user-not-found' =>
      'Correo o contraseña incorrectos.',
    'too-many-requests' =>
      'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
    'network-request-failed' =>
      'Sin conexión. Comprueba tu red e inténtalo de nuevo.',
    'popup-closed-by-user' || 'cancelled-popup-request' =>
      'Se canceló la confirmación con Google. No se ha borrado nada.',
    // Google's native selector (Android and the rest of native
    // platforms, see `FirebaseAuthRepository._nativeGoogleCredential`):
    // cancelling isn't an error, it's a valid choice by the user.
    'sign_in_canceled' => 'Se canceló el inicio de sesión con Google.',
    'user-mismatch' => 'Debes confirmar con la misma cuenta de Google.',
    'requires-recent-login' => 'Vuelve a iniciar sesión e inténtalo de nuevo.',
    'password-required' => 'Introduce tu contraseña para continuar.',
    _ => _genericMessage,
  };
}
