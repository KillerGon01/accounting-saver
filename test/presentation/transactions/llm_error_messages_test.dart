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

    test('un código desconocido cae en el mensaje genérico', () {
      expect(
        llmErrorMessage(const LlmGatewayException('codigo-que-no-existe')),
        'No se pudo interpretar el texto. Inténtalo de nuevo o añade el movimiento a mano.',
      );
    });
  });
}
