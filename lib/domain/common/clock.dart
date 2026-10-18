/// Source of the current date and time. Injected instead of calling
/// `DateTime.now()` directly, so it can be fixed in tests (see
/// `FakeClock` in `test/fakes/`).
abstract class Clock {
  DateTime now();
}

/// Real implementation: delegates to `DateTime.now()`.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
