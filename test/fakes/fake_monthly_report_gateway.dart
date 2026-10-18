import 'dart:async';

import 'package:accounting_saver/domain/reports/monthly_report.dart';
import 'package:accounting_saver/domain/reports/monthly_report_gateway.dart';

/// Configurable fake for testing [ExplainMonthlyReport] and the
/// report screen without calling Gemini.
///
/// - `.returning(...)` returns a fixed comment.
/// - `.throwing(...)` simulates a gateway error.
/// - `.pending()` doesn't respond until the test calls `complete`/
///   `completeWithError`, to test the progress indicator without
///   waiting real time (same pattern as `FakeChatGateway.pending()`).
class FakeMonthlyReportGateway implements MonthlyReportGateway {
  FakeMonthlyReportGateway.returning(this._result)
    : _error = null,
      _pending = null;

  FakeMonthlyReportGateway.throwing(Object error)
    : _error = error,
      _result = null,
      _pending = null;

  FakeMonthlyReportGateway.pending()
    : _error = null,
      _result = null,
      _pending = Completer<String>();

  final String? _result;
  final Object? _error;
  final Completer<String>? _pending;

  MonthlyReport? lastReport;
  int callCount = 0;

  void complete(String result) => _pending!.complete(result);

  void completeWithError(Object error) => _pending!.completeError(error);

  @override
  Future<String> explain(MonthlyReport report) async {
    callCount++;
    lastReport = report;
    if (_pending != null) return _pending.future;
    if (_error != null) throw _error;
    return _result!;
  }
}
