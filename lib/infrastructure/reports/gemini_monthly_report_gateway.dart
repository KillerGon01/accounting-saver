import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/monthly_report_gateway.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../common/app_check_error.dart';
import '../common/gemini_model_fallback.dart';
import '../common/gemini_transient_retry.dart';

/// Implementación de [MonthlyReportGateway] con Gemini (Firebase AI Logic,
/// Gemini Developer API): una sola llamada, sin function calling. Mismos
/// modelos, fallback, reintento y timeout que el chat y la entrada en
/// lenguaje natural (ver [geminiModelFallbacks], [withGeminiModelFallback],
/// [withTransientRetry]): comparten la misma cuota gratuita.
class GeminiMonthlyReportGateway implements MonthlyReportGateway {
  GeminiMonthlyReportGateway({GeminiModelAvailability? availability})
    : _availability = availability ?? GeminiModelAvailability();

  final GeminiModelAvailability _availability;

  static GenerativeModel _buildModel(String model) {
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      // Temperatura baja: es un comentario sobre cifras ya calculadas, no
      // redacción creativa.
      generationConfig: GenerationConfig(temperature: 0.2),
    );
  }

  @override
  Future<String> explain(MonthlyReport report) async {
    final prompt = buildMonthlyReportExplanationPrompt(report);

    String? responseText;
    try {
      responseText = await withGeminiModelFallback(
        availability: _availability,
        attempt: (model) {
          final generativeModel = _buildModel(model);
          return withTransientRetry(() async {
            final response = await generativeModel.generateContent([Content.text(prompt)]);
            return response.text;
          });
        },
      );
    } on QuotaExceeded {
      throw const LlmGatewayException(
        'quota-exceeded',
        message: 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
      );
    } on TimeoutException {
      // Igual que en `GeminiChatGateway`/`GeminiLlmGateway`: un timeout
      // nunca se reintenta (ver `gemini_transient_retry.dart`), así que
      // esto sale tras un único intento de `geminiRequestTimeout` (150 s).
      throw const LlmGatewayException(
        'timeout',
        message: 'La IA no está disponible ahora mismo.',
      );
    } on FirebaseAIException catch (error) {
      if (isModelNotFoundError(error)) {
        throw const LlmGatewayException(
          'model-not-found',
          message: 'La IA no está disponible ahora mismo.',
        );
      }
      if (isAppCheckAttestationError(error)) {
        throw const LlmGatewayException(
          'app-check-failed',
          message: 'La IA no está disponible ahora mismo.',
        );
      }
      throw LlmGatewayException('service-error', message: 'Error de la IA: ${error.message}');
    } catch (error) {
      throw const LlmGatewayException(
        'network-error',
        message: 'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
      );
    }

    if (responseText == null || responseText.trim().isEmpty) {
      throw const LlmGatewayException(
        'malformed-response',
        message: 'La IA no ha devuelto ningún comentario. Inténtalo de nuevo más tarde.',
      );
    }
    return responseText;
  }
}

/// Construye el prompt que se envía a Gemini para comentar [report].
///
/// Función pura (sin `firebase_ai` ni red), así se prueba sin ningún
/// proyecto de Firebase: ver `test/infrastructure/reports/`.
///
/// Solo recibe cifras agregadas, nunca movimientos: [MonthlyReport] no
/// tiene ningún campo para una descripción o un concepto, así que es
/// imposible que uno se filtre aquí por accidente (no es un filtrado que
/// pueda fallar, es un tipo que no transporta ese dato).
String buildMonthlyReportExplanationPrompt(MonthlyReport report) {
  final buffer = StringBuffer()
    ..writeln(
      'Eres el asistente financiero personal de la aplicación. Vas a '
      'comentar, en español de España, el resumen de un mes de los '
      'movimientos del usuario.',
    )
    ..writeln()
    ..writeln(
      'Usa solo las cifras de abajo. No inventes ningún dato, movimiento '
      'o concepto que no esté en ellas. No das ningún consejo de '
      'inversión ni asesoramiento financiero: solo comentas las cifras '
      '(por ejemplo, en qué ha gastado más, cómo compara con el mes '
      'anterior).',
    )
    ..writeln()
    ..writeln('Mes: ${report.month}/${report.year}.');

  if (report.isCurrentMonth) {
    buffer.writeln(
      'Importante: este mes aún no ha terminado. Los datos solo llegan '
      'hasta el día ${report.elapsedDays}, no hasta el final del mes. No '
      'saques conclusiones de la comparación con el mes anterior (que sí '
      'está completo) como si ambos periodos fueran equivalentes: dilo '
      'explícitamente si comentas esa comparación.',
    );
  }

  if (report.truncated) {
    buffer.writeln(
      'Importante: este informe es parcial porque se ha alcanzado el '
      'límite de movimientos leídos. Las cifras pueden no reflejar el '
      'mes completo; dilo si lo comentas.',
    );
  }

  buffer
    ..writeln()
    ..writeln('Ingresos: ${_euros(report.incomeCents)}.')
    ..writeln('Gastos: ${_euros(report.expenseCents)}.')
    ..writeln('Balance: ${_euros(report.balanceCents)}.')
    ..writeln('Número de movimientos: ${report.transactionCount}.');

  if (report.categoryBreakdown.isEmpty) {
    buffer.writeln('Sin gasto por categoría este mes.');
  } else {
    buffer.writeln('Gasto por categoría:');
    for (final expense in report.categoryBreakdown) {
      buffer.writeln(
        '- ${expense.category.name}: ${_euros(expense.amountCents)} '
        '(${expense.percentageOfExpense.toStringAsFixed(1)} % del gasto total).',
      );
    }
  }

  final comparison = report.comparison;
  if (comparison == null) {
    buffer.writeln('No hay datos del mes anterior: no compares con él.');
  } else {
    buffer
      ..writeln('Comparación con el mes anterior:')
      ..writeln(
        '- Gasto total: ${_euros(comparison.previousExpenseCents)} el mes '
        'anterior, ${_deltaDescription(comparison.expenseDeltaCents, comparison.expenseDeltaPercent)}.',
      );
    for (final entry in comparison.perCategoryDeltas.entries) {
      buffer.writeln(
        '- ${entry.key.name}: ${_euros(entry.value.previousAmountCents)} el mes anterior, '
        '${_deltaDescription(entry.value.deltaCents, entry.value.deltaPercent)}.',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln(
      'Responde con un comentario de 3 o 4 frases, en texto plano, sin '
      'ningún formato Markdown (nada de asteriscos, almohadillas ni '
      'guiones de lista).',
    );

  return buffer.toString();
}

String _deltaDescription(int deltaCents, double? deltaPercent) {
  final direction = deltaCents > 0 ? 'más' : (deltaCents < 0 ? 'menos' : 'igual');
  final percentText = deltaPercent == null ? '' : ' (${deltaPercent.abs().toStringAsFixed(1)} %)';
  return '${_euros(deltaCents.abs())} $direction que ese mes$percentText';
}

String _euros(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  final euros = _groupThousands(absolute ~/ 100);
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  return '$sign$euros,$decimals €';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
