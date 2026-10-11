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

    test('un modelo no encontrado (404) se traduce al mensaje de siempre, nunca al nombre del modelo', () {
      final message = chatErrorMessage(
        const LlmGatewayException(
          'model-not-found',
          message: 'models/gemini-2.5-flash is not found for API version v1beta.',
        ),
      );

      expect(message, 'La IA no está disponible ahora mismo.');
      expect(message, isNot(contains('gemini-2.5-flash')));
    });

    test('tope de preguntas de la sesión', () {
      expect(
        chatErrorMessage(const LlmGatewayException('session-limit-reached')),
        contains('máximo de preguntas'),
      );
    });

    test('un "service-error" sin clasificar cae en el mensaje genérico, nunca en el texto crudo del error', () {
      // El mismo "message" que de verdad devolvió Gemini para un modelo
      // retirado para proyectos nuevos, antes de clasificarlo (ver
      // `isModelNotFoundError`): aquí se comprueba que, aunque llegara sin
      // clasificar, `chatErrorMessage` nunca lo traslada a la interfaz.
      final message = chatErrorMessage(
        const LlmGatewayException(
          'service-error',
          message: 'Error de la IA: This model models/gemini-2.5-flash-lite is no longer available '
              'to new users. Please update your code to use models/gemini-3.5-flash-lite.',
        ),
      );

      expect(message, 'La IA no está disponible ahora mismo.');
      expect(message, isNot(contains('gemini-2.5-flash-lite')));
      expect(message, isNot(contains('{')));
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
