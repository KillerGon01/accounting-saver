import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestions_gateway.dart';
import '../../domain/savings/savings_suggestions_summary.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../common/app_check_error.dart';
import '../common/gemini_model_fallback.dart';
import '../common/gemini_transient_retry.dart';

/// Implementación de [SavingsSuggestionsGateway] con Gemini (Firebase AI
/// Logic, Gemini Developer API): una sola llamada, sin function calling.
/// Mismos modelos, fallback, reintento y timeout que el resto de la app
/// (ver [geminiModelFallbacks], [withGeminiModelFallback],
/// [withTransientRetry]): comparten la misma cuota gratuita.
class GeminiSavingsSuggestionsGateway implements SavingsSuggestionsGateway {
  GeminiSavingsSuggestionsGateway({GeminiModelAvailability? availability})
    : _availability = availability ?? GeminiModelAvailability();

  final GeminiModelAvailability _availability;

  static GenerativeModel _buildModel(String model) {
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      // Temperatura baja, igual que `GeminiMonthlyReportGateway`: es una
      // redacción sobre cifras ya calculadas, no redacción creativa.
      generationConfig: GenerationConfig(temperature: 0.2),
    );
  }

  @override
  Future<String> explain(SavingsSuggestionsSummary summary) async {
    final prompt = buildSavingsSuggestionsExplanationPrompt(summary);

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
      // Igual que en `GeminiMonthlyReportGateway`/`GeminiChatGateway`: un
      // timeout nunca se reintenta (ver `gemini_transient_retry.dart`), así
      // que esto sale tras un único intento de `geminiRequestTimeout` (150 s).
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
        message: 'La IA no ha devuelto ningún resumen. Inténtalo de nuevo más tarde.',
      );
    }
    return responseText;
  }
}

/// Construye el prompt que se envía a Gemini para redactar un resumen de
/// [summary]. Función pura (sin `firebase_ai` ni red), así se prueba sin
/// ningún proyecto de Firebase: ver `test/infrastructure/savings/`.
///
/// Solo recibe el resumen agregado, nunca la meta ni ningún movimiento:
/// [SavingsSuggestionsSummary] no tiene ningún campo para un nombre, una
/// descripción o un concepto, así que es imposible que uno se filtre aquí
/// por accidente (no es un filtrado que pueda fallar, es un tipo que no
/// transporta ese dato).
String buildSavingsSuggestionsExplanationPrompt(SavingsSuggestionsSummary summary) {
  final buffer = StringBuffer()
    ..writeln(
      'Eres el asistente financiero personal de la aplicación. Vas a '
      'redactar, en español de España, un resumen en prosa de las opciones '
      'de ahorro de una meta del usuario, ya calculadas por la aplicación '
      '(nunca por ti).',
    )
    ..writeln()
    ..writeln(
      'Usa solo las cifras y las líneas de abajo. Cópialas EXACTAMENTE '
      'como aparecen, sin recalcular ningún importe, sin redondearlo y sin '
      'escribirlo con palabras (ni "cincuenta y ocho euros con noventa y '
      'ocho céntimos" ni ninguna otra forma: siempre el número tal cual, '
      'con el símbolo €). No inventes ningún importe, concepto u opción '
      'que no esté en ellas.',
    )
    ..writeln()
    ..writeln(
      'No das ningún consejo de inversión ni de productos financieros. No '
      'dices "deberías" ni "te recomiendo": las opciones de abajo son '
      'posibilidades que la aplicación ya ha calculado, nunca una '
      'recomendación tuya, y la decisión es siempre del usuario. Tampoco '
      'juzgas si la meta es alcanzable, ni animas ni presionas ("vas '
      'bien", "tienes que apretar el cinturón", "no llegas"): solo '
      'describes las opciones y sus importes, sin opinar sobre si el '
      'usuario lo está haciendo bien o mal.',
    )
    ..writeln()
    ..writeln('Objetivo de la meta: ${summary.targetFormatted}.')
    ..writeln('Ya ahorrado: ${summary.savedFormatted}.')
    ..writeln('Aportación mensual necesaria: ${summary.monthlyContributionFormatted}.')
    ..writeln('Meses restantes: ${summary.monthsRemaining}.')
    ..writeln('Estado: ${_statusLabel(summary.status)}.')
    ..writeln('Total que estas opciones podrían cubrir cada mes: ${summary.monthlyCoveredFormatted}.');

  if (summary.recurringByCategory.isEmpty &&
      summary.categoryCuts.isEmpty &&
      summary.oneOffExcesses.isEmpty) {
    buffer
      ..writeln()
      ..writeln('No hay ninguna opción de ahorro calculada para esta meta. Dilo explícitamente.');
  } else {
    if (summary.recurringByCategory.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Gastos recurrentes detectados:');
      for (final item in summary.recurringByCategory) {
        buffer.writeln('- ${item.line}');
      }
    }
    if (summary.categoryCuts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Recortes porcentuales posibles:');
      for (final item in summary.categoryCuts) {
        buffer.writeln('- ${item.line}');
      }
    }
    if (summary.oneOffExcesses.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Gastos puntuales de este mes por encima de lo habitual (no se repiten cada mes):');
      for (final item in summary.oneOffExcesses) {
        buffer.writeln('- ${item.line}');
      }
    }
  }

  buffer
    ..writeln()
    ..writeln(
      'Responde con un máximo de 4 frases cortas, en texto plano, sin '
      'ningún formato Markdown (nada de asteriscos, almohadillas ni '
      'guiones de lista), sin citar estas instrucciones. No empieces la '
      'respuesta por "la aplicación" ni por ninguna variante de esa '
      'frase, y no describas cómo se ha hecho el cálculo (nada de "se '
      'han calculado", "a partir de tus gastos" o similar): ve directo a '
      'las opciones. Escribe cada importe exactamente como llega, con su '
      'unidad pegada a la cifra (si llega "19,66 €", escribe "19,66 €", '
      'nunca lo separes en "19,66" y "euros" en frases distintas, ni le '
      'añadas ni le quites nada).',
    );

  return buffer.toString();
}

String _statusLabel(SavingsGoalStatus status) {
  return switch (status) {
    SavingsGoalStatus.completed => 'cumplida',
    SavingsGoalStatus.onTrack => 'en camino',
    SavingsGoalStatus.behind => 'por detrás',
    SavingsGoalStatus.overdue => 'vencida',
  };
}
