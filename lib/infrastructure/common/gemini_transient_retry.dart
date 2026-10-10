import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';

/// Cuánto se espera antes del único reintento ante un fallo transitorio del
/// servidor (ver [withTransientRetry]).
const geminiTransientRetryDelay = Duration(milliseconds: 1500);

/// Tope de tiempo para una sola llamada a `generateContent`, único sitio
/// donde se define este valor (ver [withTransientRetry], que lo aplica a
/// cada intento). 150 s: la latencia observada de verdad en la web
/// desplegada (Gemini 3.8 Flash, nivel gratuito) llegó a 84 s en una
/// llamada y 108 s en otra — con el valor anterior (90 s), la segunda
/// habría cortado una respuesta que Google sí iba a entregar, mostrando
/// "La IA no está disponible ahora mismo" sin que hubiera ningún fallo
/// real (ver docs/design.md). Un timeout NUNCA se reintenta (ver
/// [isTransientGeminiError]): el cliente no puede cancelar la petición ya
/// enviada al servidor (`.timeout()` solo deja de esperar en el cliente,
/// ver la limitación documentada en docs/design.md), así que reintentar
/// duplicaría una petición que podría seguir procesándose en el backend,
/// gastando el doble de cuota por una sola pregunta. El peor caso antes de
/// "La IA no está disponible ahora mismo" ante un timeout es, por tanto,
/// un único tiempo de espera de este valor, no dos.
const geminiRequestTimeout = Duration(seconds: 150);

/// Si [error] es un fallo transitorio —temporal, no de cuota— al generar
/// contenido: un 503, `UNAVAILABLE` o "Deadline expired" que el propio
/// servidor de Gemini ha devuelto como respuesta. `HttpApiClient.makeRequest`
/// (paquete `firebase_ai` 4.0.0, `lib/src/client.dart`) lanza un
/// `FirebaseAIException` liso (ni `QuotaExceeded` ni ninguna otra subclase)
/// con el cuerpo de la respuesta completo en el mensaje cuando el backend
/// devuelve un código 5xx, así que comprobamos el texto en vez del tipo.
/// [QuotaExceeded] se descarta explícitamente aunque también implemente
/// `FirebaseAIException`: la cuota agotada la gestiona
/// `withGeminiModelFallback` pasando de modelo, no esperando y reintentando
/// el mismo.
///
/// Un [TimeoutException] (ver [geminiRequestTimeout]) NO es transitorio a
/// estos efectos, a propósito: a diferencia de un 503 (el servidor ya ha
/// terminado y ha contestado que lo intentes más tarde), un timeout solo
/// significa que el cliente ha dejado de esperar; el servidor puede seguir
/// procesando esa misma petición. Reintentarlo enviaría una segunda
/// petición sin saber si la primera va a acabar respondiendo, así que
/// [withTransientRetry] lo relanza de inmediato, sin reintento.
bool isTransientGeminiError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('UNAVAILABLE') ||
      message.contains('Deadline expired') ||
      message.contains('Server Error [503]');
}

/// Reintenta [attempt] una sola vez, tras [delay], si falla con un error
/// transitorio del servidor ([isTransientGeminiError]). El intento inicial
/// se corta a los [timeout] con un [TimeoutException] si el servidor no
/// responde a tiempo; un timeout nunca se reintenta (ver el porqué en
/// [isTransientGeminiError]), se relanza de inmediato igual que cualquier
/// otro error no transitorio (incluida la cuota agotada), para que lo
/// gestione quien llame (por ejemplo, `withGeminiModelFallback` pasando al
/// siguiente modelo). Como mucho un intento extra por llamada, nunca un
/// bucle, y solo ante un 503/`UNAVAILABLE`/"Deadline expired"; el
/// reintento usa el mismo [attempt] (el mismo modelo), no otro de la lista
/// de fallback, y no se marca el modelo como agotado (eso solo lo hace
/// `withGeminiModelFallback` ante cuota agotada).
Future<T> withTransientRetry<T>(
  Future<T> Function() attempt, {
  Duration delay = geminiTransientRetryDelay,
  Duration timeout = geminiRequestTimeout,
}) async {
  try {
    return await attempt().timeout(timeout);
  } catch (error) {
    if (!isTransientGeminiError(error)) rethrow;
    await Future<void>.delayed(delay);
    return attempt().timeout(timeout);
  }
}
