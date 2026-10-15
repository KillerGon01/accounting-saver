import 'dart:async';

import 'package:accounting_saver/domain/savings/savings_suggestions_gateway.dart';
import 'package:accounting_saver/domain/savings/savings_suggestions_summary.dart';

/// Fake configurable para probar [ExplainSavingsSuggestions] y la hoja de
/// sugerencias sin llamar a Gemini. Mismo patrón que
/// `FakeMonthlyReportGateway`.
class FakeSavingsSuggestionsGateway implements SavingsSuggestionsGateway {
  FakeSavingsSuggestionsGateway.returning(this._result)
    : _error = null,
      _pending = null;

  FakeSavingsSuggestionsGateway.throwing(Object error)
    : _error = error,
      _result = null,
      _pending = null;

  FakeSavingsSuggestionsGateway.pending()
    : _error = null,
      _result = null,
      _pending = Completer<String>();

  final String? _result;
  final Object? _error;
  final Completer<String>? _pending;

  SavingsSuggestionsSummary? lastSummary;
  int callCount = 0;

  void complete(String result) => _pending!.complete(result);

  void completeWithError(Object error) => _pending!.completeError(error);

  @override
  Future<String> explain(SavingsSuggestionsSummary summary) async {
    callCount++;
    lastSummary = summary;
    if (_pending != null) return _pending.future;
    if (_error != null) throw _error;
    return _result!;
  }
}
