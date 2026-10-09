import 'package:firebase_ai/firebase_ai.dart';

/// Si [error] señala que el backend de Gemini ha rechazado la petición
/// porque el token de App Check no es válido: 403, `PERMISSION_DENIED`,
/// "App attestation failed" — visto de verdad probando el chat el 8 de
/// octubre de 2026, al activar App Check. No es un problema de cuota ni
/// un fallo transitorio del servidor: no debe reintentarse
/// ([withTransientRetry] no lo reintenta porque su mensaje no contiene
/// `UNAVAILABLE`, `Deadline expired` ni `Server Error [503]`) ni marcar el
/// modelo como agotado ([withGeminiModelFallback] solo actúa sobre
/// [QuotaExceeded], y este error no lo es). Solo hay que traducirlo al
/// mensaje de siempre, nunca mostrar el JSON crudo del error al usuario.
bool isAppCheckAttestationError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('App attestation failed') || message.contains('PERMISSION_DENIED');
}
