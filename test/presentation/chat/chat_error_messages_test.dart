import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/presentation/chat/chat_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatErrorMessage', () {
    test('un token de App Check inválido se traduce al mensaje de siempre, nunca al JSON crudo', () {
      final message = chatErrorMessage(
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

    test('cuota agotada', () {
      expect(
        chatErrorMessage(const LlmGatewayException('quota-exceeded')),
        'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
      );
    });

    test('un timeout se traduce al mensaje de siempre', () {
      expect(
        chatErrorMessage(const LlmGatewayException('timeout', message: 'La IA no está disponible ahora mismo.')),
        'La IA no está disponible ahora mismo.',
      );
    });

    test('tope de preguntas de la sesión', () {
      expect(
        chatErrorMessage(const LlmGatewayException('session-limit-reached')),
        contains('máximo de preguntas'),
      );
    });

    test('un código desconocido cae en el mensaje genérico', () {
      expect(
        chatErrorMessage(const LlmGatewayException('codigo-que-no-existe')),
        'La IA no está disponible ahora mismo.',
      );
    });

    test('un error que no es LlmGatewayException cae en el mensaje genérico', () {
      expect(chatErrorMessage(Exception('algo inesperado')), 'La IA no está disponible ahora mismo.');
    });
  });
}
