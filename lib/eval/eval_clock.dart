import '../domain/common/clock.dart';

/// Reloj fijo para que la evaluación de calidad del chat (ver
/// `docs/evaluation.md`) sea reproducible: el executor de funciones del
/// chat (`TransactionChatFunctions`) y la instrucción de sistema de Gemini
/// (`buildChatSystemInstruction`, en `GeminiChatGateway`) reciben ambos la
/// misma fecha, en vez del reloj real del dispositivo que ejecute el
/// harness. Vive en `lib/` (no en `test/`) porque la usa `eval_main.dart`,
/// que no es un test.
class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
