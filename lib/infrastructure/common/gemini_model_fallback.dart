import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/common/clock.dart';

/// Modelos de Gemini a probar en orden cuando el primero devuelve cuota
/// agotada (429 / `RESOURCE_EXHAUSTED`), todos en el nivel gratuito de la
/// Gemini Developer API. Lista única para que el chat y la entrada en
/// lenguaje natural compartan el mismo criterio y, a través de
/// [GeminiModelAvailability], la misma memoria de qué modelo está agotado:
/// los dos gastan la misma cuota diaria del proyecto.
const geminiModelFallbacks = <String>[
  'gemini-3.8-flash',
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
];

/// Cuánto se recuerda que un modelo está agotado antes de volver a probarlo.
const geminiModelExhaustionDuration = Duration(hours: 1);

/// Recuerda en memoria, durante [geminiModelExhaustionDuration] o hasta que
/// se reinicie la app, qué modelos de [geminiModelFallbacks] han devuelto
/// cuota agotada, para no gastar una petición reintentando un modelo que ya
/// sabemos que va a fallar.
///
/// Pensada como una sola instancia compartida por toda la app (ver los
/// providers): el chat y la entrada en lenguaje natural gastan la misma
/// cuota diaria del proyecto, así que deben compartir esta memoria.
class GeminiModelAvailability {
  // ignore: prefer_initializing_formals (el nombre público es `clock`, no `_clock`)
  GeminiModelAvailability({Clock clock = const SystemClock()}) : _clock = clock;

  final Clock _clock;
  final _exhaustedUntil = <String, DateTime>{};

  bool isAvailable(String model) {
    final until = _exhaustedUntil[model];
    if (until == null) return true;
    if (_clock.now().isBefore(until)) return false;
    _exhaustedUntil.remove(model);
    return true;
  }

  void markExhausted(String model) {
    _exhaustedUntil[model] = _clock.now().add(geminiModelExhaustionDuration);
  }
}

/// Prueba [attempt] con el primer modelo disponible de [models] según
/// [availability]; si falla con cuota agotada ([QuotaExceeded]), lo marca
/// como agotado en [availability] y reintenta una sola vez con el siguiente
/// modelo disponible de la lista, así hasta que uno responda o se acaben
/// los modelos. Sin bucles: como mucho un intento por modelo de la lista en
/// esta misma llamada.
///
/// Lanza [QuotaExceeded] si no queda ningún modelo disponible (todos
/// agotados ya) o si todos los intentos de esta llamada fallan con cuota
/// agotada.
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
    }
  }
  throw StateError('unreachable');
}
