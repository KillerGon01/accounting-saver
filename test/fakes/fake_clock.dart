import 'package:accounting_saver/domain/common/clock.dart';

/// Fixed clock for tests: always returns the same date.
class FakeClock implements Clock {
  FakeClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
