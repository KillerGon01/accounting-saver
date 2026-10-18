import '../../domain/payroll/payroll_file_exception.dart';
import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'No se pudo leer la nómina. Inténtalo de nuevo.';

/// Spanish-language message for an error reading a payroll with AI.
/// Reuses the same [LlmGatewayException] codes as natural language
/// input (see `llm_error_messages.dart`), with the text adapted to
/// "nómina" instead of "texto".
String payrollErrorMessage(Object error) {
  if (error is PayrollFileException) return error.message;
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' =>
      'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'app-check-failed' => 'La IA no está disponible ahora mismo.',
    'timeout' => 'La IA no está disponible ahora mismo.',
    'model-not-found' => 'La IA no está disponible ahora mismo.',
    'session-limit-reached' => error.message ?? _genericMessage,
    _ => _genericMessage,
  };
}
