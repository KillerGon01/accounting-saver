import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/presentation/transactions/llm_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('llmErrorMessage', () {
    test('un token de App Check inválido se traduce al mensaje de IA no disponible, no al JSON crudo', () {
      final message = llmErrorMessage(
        const LlmGatewayException(
          'app-check-failed',
          message: '{"error":{"code":403,"status":"PERMISSION_DENIED",'
              '"message":"App attestation failed."}}',
        ),
      );

      expect(message, 'La IA no está disponible ahora mismo.');
      expect(message, isNot(contains('{')));
      expect(message, isNot(contains('PERMISSION_DENIED')));
    });

    test('un timeout se traduce al mensaje de IA no disponible, no al genérico de texto', () {
      expect(
        llmErrorMessage(const LlmGatewayException('timeout', message: 'La IA no está disponible ahora mismo.')),
        'La IA no está disponible ahora mismo.',
      );
    });

    test('un modelo no encontrado (404) se traduce al mensaje de IA no disponible, no al genérico de texto', () {
      final message = llmErrorMessage(
        const LlmGatewayException(
          'model-not-found',
          message: 'models/gemini-2.5-flash is not found for API version v1beta.',
        ),
      );

      expect(message, 'La IA no está disponible ahora mismo.');
      expect(message, isNot(contains('gemini-2.5-flash')));
    });

    test('cuota agotada', () {
      expect(
        llmErrorMessage(const LlmGatewayException('quota-exceeded')),
        contains('cuota gratuita'),
      );
    });

    test('un "service-error" sin clasificar cae en el genérico, nunca en el texto crudo ni el modelo', () {
      final message = llmErrorMessage(
        const LlmGatewayException(
          'service-error',
          message: 'No se pudo generar el movimiento con la IA: This model '
              'models/gemini-2.5-flash-lite is no longer available to new users. '
              'Please update your code to use models/gemini-3.5-flash-lite.',
        ),
      );

      expect(message, 'No se pudo interpretar el texto. Inténtalo de nuevo o añade el movimiento a mano.');
      expect(message, isNot(contains('gemini-2.5-flash-lite')));
      expect(message, isNot(contains('{')));
    });

    test('un código desconocido cae en el mensaje genérico', () {
      expect(
        llmErrorMessage(const LlmGatewayException('codigo-que-no-existe')),
        'No se pudo interpretar el texto. Inténtalo de nuevo o añade el movimiento a mano.',
      );
    });
  });
}
