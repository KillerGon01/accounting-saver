import 'package:accounting_saver/domain/common/clock.dart';

/// Reloj fijo para los tests: siempre devuelve la misma fecha.
class FakeClock implements Clock {
  FakeClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
