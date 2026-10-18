import 'raw_parsed_transaction.dart';

/// Port to a language model able to extract a transaction from free
/// text. The infrastructure layer (Gemini) implements this interface;
/// the domain and application layers don't know the provider.
abstract class LlmGateway {
  /// Extracts a transaction from [text]. [now] is used to resolve
  /// relative dates ("yesterday", "last Monday").
  ///
  /// If the text doesn't clearly describe a transaction with an
  /// amount, the result has `understood: false` and the rest of the
  /// fields are `null`; it doesn't throw for that.
  ///
  /// Throws [LlmGatewayException] if the AI isn't available (quota,
  /// network) or if the response can't be parsed.
  Future<RawParsedTransaction> extractTransaction({
    required String text,
    required DateTime now,
  });
}
