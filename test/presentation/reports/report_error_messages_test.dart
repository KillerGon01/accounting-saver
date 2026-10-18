import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/presentation/reports/report_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reportErrorMessage', () {
    test('un token de App Check inválido se traduce al mensaje de siempre, nunca al JSON crudo', () {
      final message = reportErrorMessage(
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

    test('un modelo no encontrado (404) se traduce al mensaje de siempre, nunca al nombre del modelo', () {
      final message = reportErrorMessage(
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
        reportErrorMessage(const LlmGatewayException('quota-exceeded')),
        contains('cuota gratuita'),
      );
    });

    test('tope de comentarios de la sesión', () {
      expect(
        reportErrorMessage(const LlmGatewayException('comment-limit-reached')),
        contains('máximo de comentarios'),
      );
    });

    test('un "service-error" sin clasificar cae en el mensaje genérico, nunca en el texto crudo del error', () {
      // The same "message" Gemini actually returned for a model retired
      // for new projects, before classifying it (see
      // `isModelNotFoundError`): this checks that, even if it arrived
      // unclassified, `reportErrorMessage` never passes it through to the UI.
      final message = reportErrorMessage(
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
        reportErrorMessage(const LlmGatewayException('codigo-que-no-existe')),
        'La IA no está disponible ahora mismo.',
      );
    });

    test('un error que no es LlmGatewayException cae en el mensaje genérico', () {
      expect(reportErrorMessage(Exception('algo inesperado')), 'La IA no está disponible ahora mismo.');
    });

    test('un StateError (petición ya en curso) tiene su propio mensaje', () {
      expect(
        reportErrorMessage(StateError('ya hay una petición en curso')),
        'Espera a que termine de generarse el comentario anterior.',
      );
    });
  });
}
