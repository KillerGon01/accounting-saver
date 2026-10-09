import 'package:firebase_ai/firebase_ai.dart';

/// Cuánto se espera antes del único reintento ante un fallo transitorio del
/// servidor (ver [withTransientRetry]).
const geminiTransientRetryDelay = Duration(milliseconds: 1500);

/// Si [error] es un fallo transitorio del servidor de Gemini —503,
/// `UNAVAILABLE` o "Deadline expired" al generar contenido—, no de cuota.
/// `HttpApiClient.makeRequest` (paquete `firebase_ai` 4.0.0,
/// `lib/src/client.dart`) lanza un `FirebaseAIException` liso (ni
/// `QuotaExceeded` ni ninguna otra subclase) con el cuerpo de la respuesta
/// completo en el mensaje cuando el backend devuelve un código 5xx, así que
/// comprobamos el texto en vez del tipo. [QuotaExceeded] se descarta
/// explícitamente aunque también implemente `FirebaseAIException`: la
/// cuota agotada la gestiona `withGeminiModelFallback` pasando de modelo,
/// no esperando y reintentando el mismo.
bool isTransientGeminiError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('UNAVAILABLE') ||
      message.contains('Deadline expired') ||
      message.contains('Server Error [503]');
}

/// Reintenta [attempt] una sola vez, tras [delay], si falla con un error
/// transitorio del servidor ([isTransientGeminiError]). Ante cualquier otro
/// error (incluida la cuota agotada) no reintenta: se relanza de inmediato
/// para que lo gestione quien llame (por ejemplo, `withGeminiModelFallback`
/// pasando al siguiente modelo). Como mucho un intento extra por llamada,
/// nunca un bucle; el reintento usa el mismo [attempt] (el mismo modelo),
/// no otro de la lista de fallback.
Future<T> withTransientRetry<T>(
  Future<T> Function() attempt, {
  Duration delay = geminiTransientRetryDelay,
}) async {
  try {
    return await attempt();
  } catch (error) {
    if (!isTransientGeminiError(error)) rethrow;
    await Future<void>.delayed(delay);
    return attempt();
  }
}
