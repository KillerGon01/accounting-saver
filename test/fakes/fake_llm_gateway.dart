import 'package:accounting_saver/domain/transactions/llm_gateway.dart';
import 'package:accounting_saver/domain/transactions/raw_parsed_transaction.dart';

/// Fake configurable con un resultado o un error fijo, para probar
/// [ParseNaturalLanguageTransaction] sin llamar a Gemini.
class FakeLlmGateway implements LlmGateway {
  FakeLlmGateway.returning(this._result) : _error = null;

  FakeLlmGateway.throwing(Object error)
      : _error = error,
        _result = null;

  final RawParsedTransaction? _result;
  final Object? _error;

  String? lastText;
  DateTime? lastNow;

  @override
  Future<RawParsedTransaction> extractTransaction({
    required String text,
    required DateTime now,
  }) async {
    lastText = text;
    lastNow = now;
    if (_error != null) throw _error;
    return _result!;
  }
}
