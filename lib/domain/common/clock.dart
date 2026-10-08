/// Fuente de la fecha y hora actuales. Se inyecta en vez de llamar a
/// `DateTime.now()` directamente, para poder fijarla en los tests (ver
/// `FakeClock` en `test/fakes/`).
abstract class Clock {
  DateTime now();
}

/// Implementación real: delega en `DateTime.now()`.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
