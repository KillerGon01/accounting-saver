/// Error extracting a transaction with the AI, independent of the
/// provider. The infrastructure layer translates its own errors
/// (quota, network, unexpected response) into this type, and the
/// presentation layer decides the message to show based on [code].
class LlmGatewayException implements Exception {
  const LlmGatewayException(this.code, {this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'LlmGatewayException($code)';
}
