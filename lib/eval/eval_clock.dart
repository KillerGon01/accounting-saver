import '../domain/common/clock.dart';

/// Fixed clock so the chat's quality evaluation (see
/// `docs/evaluation.md`) is reproducible: the chat's function
/// executor (`TransactionChatFunctions`) and Gemini's system
/// instruction (`buildChatSystemInstruction`, in `GeminiChatGateway`)
/// both receive the same date, instead of the real clock of the
/// device running the harness. Lives in `lib/` (not in `test/`)
/// because `eval_main.dart` uses it, which isn't a test.
class FixedClock implements Clock {
  const FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
