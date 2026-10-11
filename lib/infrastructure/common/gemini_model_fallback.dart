import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/common/clock.dart';

/// Modelos de Gemini a probar en orden cuando el primero devuelve cuota
/// agotada (429 / `RESOURCE_EXHAUSTED`), todos en el nivel gratuito de la
/// Gemini Developer API. Lista única para que el chat y la entrada en
/// lenguaje natural compartan el mismo criterio y, a través de
/// [GeminiModelAvailability], la misma memoria de qué modelo está agotado:
/// los dos gastan la misma cuota diaria del proyecto.
const geminiModelFallbacks = <String>[
  'gemini-3.5-flash-lite',
  'gemini-3.8-flash',
];

/// Cuánto se recuerda que un modelo está agotado antes de volver a probarlo.
const geminiModelExhaustionDuration = Duration(hours: 1);

/// Recuerda en memoria, durante [geminiModelExhaustionDuration] o hasta que
/// se reinicie la app, qué modelos de [geminiModelFallbacks] han devuelto
/// cuota agotada, para no gastar una petición reintentando un modelo que ya
/// sabemos que va a fallar. También recuerda, hasta que se reinicie la app
/// (sin expirar, a diferencia de la cuota agotada), qué modelos no existen
/// ya en la API — ver [markUnavailableForSession].
///
/// Pensada como una sola instancia compartida por toda la app (ver los
/// providers): el chat y la entrada en lenguaje natural gastan la misma
/// cuota diaria del proyecto, así que deben compartir esta memoria.
class GeminiModelAvailability {
  // ignore: prefer_initializing_formals (el nombre público es `clock`, no `_clock`)
  GeminiModelAvailability({Clock clock = const SystemClock()}) : _clock = clock;

  final Clock _clock;
  final _exhaustedUntil = <String, DateTime>{};
  final _unavailableForSession = <String>{};

  bool isAvailable(String model) {
    if (_unavailableForSession.contains(model)) return false;
    final until = _exhaustedUntil[model];
    if (until == null) return true;
    if (_clock.now().isBefore(until)) return false;
    _exhaustedUntil.remove(model);
    return true;
  }

  void markExhausted(String model) {
    _exhaustedUntil[model] = _clock.now().add(geminiModelExhaustionDuration);
  }

  /// Para un modelo que ya no existe en la API (404 `NOT_FOUND`, ver
  /// [isModelNotFoundError]), no uno con la cuota agotada: reintentarlo no
  /// va a hacer que empiece a existir, así que, a diferencia de
  /// [markExhausted], esto no expira con el tiempo — solo se olvida al
  /// reiniciar la app (una instancia nueva de [GeminiModelAvailability]).
  void markUnavailableForSession(String model) {
    _unavailableForSession.add(model);
  }
}

/// `true` si [error] indica que un modelo de Gemini no existe o ya no está
/// disponible en esta API: un 404 cuyo mensaje empieza por
/// "models/&lt;nombre&gt; is not found for API version...". Se ve, por
/// ejemplo, al pedir un modelo retirado (los `gemini-2.5-*` de
/// [geminiModelFallbacks] están anunciados para apagarse en octubre de
/// 2026).
///
/// El paquete `firebase_ai` (4.0.0, `lib/src/error.dart`, función
/// `parseError`) no tiene un tipo propio para esto —comprobado con la
/// fixture del propio paquete (`test/google_ai_response_parsing_test.dart`,
/// caso "for general server errors")—: un 404 de modelo inexistente cae en
/// `ServerException`, el mismo tipo que cualquier otro fallo del servidor
/// sin clasificar. Así que, igual que [isTransientGeminiError] e
/// `isAppCheckAttestationError`, hay que mirar el texto del mensaje en vez
/// del tipo.
bool isModelNotFoundError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  return error.message.contains('is not found for API version');
}

/// Prueba [attempt] con el primer modelo disponible de [models] según
/// [availability]. Ante cuota agotada ([QuotaExceeded]), lo marca como
/// agotado (temporalmente, [GeminiModelAvailability.markExhausted]) y
/// reintenta con el siguiente modelo disponible de la lista. Ante un
/// modelo inexistente ([isModelNotFoundError]), hace lo mismo pero lo marca
/// como no disponible para toda la sesión
/// ([GeminiModelAvailability.markUnavailableForSession], sin expirar). En
/// los dos casos, así hasta que uno responda o se acaben los modelos: sin
/// bucles, como mucho un intento por modelo de la lista en esta misma
/// llamada. Cualquier otro error (503, timeout, 403 de App Check...) se
/// relanza de inmediato, sin probar otro modelo — lo gestiona quien llame.
///
/// Lanza [QuotaExceeded] si no queda ningún modelo disponible (todos
/// agotados o inexistentes ya) o si todos los intentos de esta llamada
/// fallan con cuota agotada; relanza el error del último intento si todos
/// fallan por ser modelos inexistentes.
Future<T> withGeminiModelFallback<T>({
  required GeminiModelAvailability availability,
  required Future<T> Function(String model) attempt,
  List<String> models = geminiModelFallbacks,
}) async {
  final candidates = models.where(availability.isAvailable).toList();
  if (candidates.isEmpty) {
    throw QuotaExceeded('Todos los modelos de Gemini están agotados temporalmente.');
  }

  for (var i = 0; i < candidates.length; i++) {
    try {
      return await attempt(candidates[i]);
    } on QuotaExceeded {
      availability.markExhausted(candidates[i]);
      if (i == candidates.length - 1) rethrow;
    } catch (error) {
      if (!isModelNotFoundError(error)) rethrow;
      availability.markUnavailableForSession(candidates[i]);
      if (i == candidates.length - 1) rethrow;
    }
  }
  throw StateError('unreachable');
}
