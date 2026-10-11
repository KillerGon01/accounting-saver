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
/// disponible en esta API. Dos formas vistas de verdad, ninguna del todo
/// fiable por sí sola, así que se comprueban las dos:
/// - Un modelo retirado de la API: "models/&lt;nombre&gt; is not found for
///   API version...".
/// - Un modelo ya no disponible para proyectos nuevos (así es como han
///   empezado a devolver los `gemini-2.5-*`, antes de que la API los
///   retire del todo): "This model models/&lt;nombre&gt; is no longer
///   available to new users. Please update your code to use
///   models/&lt;otro&gt; ...".
///
/// El paquete `firebase_ai` (4.0.0, `lib/src/error.dart`, función
/// `parseError`) no expone el código HTTP (404) ni el `status` del cuerpo
/// del error ("NOT_FOUND"): los dos casos de arriba llegan como un 404 con
/// cuerpo `{"error": {"code": 404, "message": "...", "status":
/// "NOT_FOUND"}}`, pero el `switch` de `parseError` solo mira `message` (y,
/// para otros tipos, `details`/`status` de casos muy concretos que no son
/// este); cualquier error con un campo `message` de texto que no encaje en
/// esos otros casos —éste incluido— cae en el `ServerException` genérico,
/// que solo guarda ese texto. Comprobado con la fixture del propio paquete
/// (`test/google_ai_response_parsing_test.dart`, caso "for general server
/// errors"): no hay ningún campo de código o estado que mirar en el
/// `error` de Dart, solo el texto. Así que, igual que [isTransientGeminiError]
/// e `isAppCheckAttestationError`, hay que mirar el texto del mensaje en
/// vez del tipo o de un código que el paquete no conserva.
bool isModelNotFoundError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('is not found for API version') || message.contains('no longer available');
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
