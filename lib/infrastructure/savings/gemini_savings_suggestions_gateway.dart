import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestions_gateway.dart';
import '../../domain/savings/savings_suggestions_summary.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../common/app_check_error.dart';
import '../common/gemini_model_fallback.dart';
import '../common/gemini_transient_retry.dart';

/// [SavingsSuggestionsGateway] implementation with Gemini (Firebase AI
/// Logic, Gemini Developer API): a single call, no function calling.
/// Same models, fallback, retry and timeout as the rest of the app
/// (see [geminiModelFallbacks], [withGeminiModelFallback],
/// [withTransientRetry]): they share the same free quota.
class GeminiSavingsSuggestionsGateway implements SavingsSuggestionsGateway {
  GeminiSavingsSuggestionsGateway({GeminiModelAvailability? availability})
    : _availability = availability ?? GeminiModelAvailability();

  final GeminiModelAvailability _availability;

  static GenerativeModel _buildModel(String model) {
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      // Low temperature, same as `GeminiMonthlyReportGateway`: this is
      // a write-up of already-computed figures, not creative writing.
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
      // Same as in `GeminiMonthlyReportGateway`/`GeminiChatGateway`: a
      // timeout is never retried (see `gemini_transient_retry.dart`),
      // so this comes out after a single `geminiRequestTimeout`
      // (150 s) attempt.
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

/// Builds the prompt sent to Gemini to write up a summary of
/// [summary]. Pure function (no `firebase_ai`, no network), so it's
/// tested without any Firebase project: see
/// `test/infrastructure/savings/`.
///
/// Only receives the aggregated summary, never the goal or any
/// transaction: [SavingsSuggestionsSummary] has no field for a name,
/// a description, or a concept, so it's impossible for one to leak in
/// here by accident (it's not a filtering step that could fail, it's
/// a type that doesn't carry that data).
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
    ..writeln('Total que estas opciones podrían cubrir cada mes: ${summary.monthlyCoveredFormatted}.')
    ..writeln()
    ..writeln('Línea de cobertura ya redactada (cópiala tal cual, es la frase (a) de la estructura de abajo):')
    ..writeln(summary.coverageLine);

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
      'Responde con un MÁXIMO de 4 frases cortas, en este orden exacto, '
      'una idea por frase:',
    )
    ..writeln(
      '(a) La línea de cobertura de arriba, copiada tal cual (puedes '
      'ajustar solo lo mínimo para que encadene con el resto del texto, '
      'nunca sus importes ni su sentido).',
    )
    ..writeln(
      '(b) Las opciones mensuales (recurrentes y recortes) con sus '
      'importes copiados tal cual de las líneas de arriba.',
    )
    ..writeln(
      '(c) Si hay algún gasto puntual por encima de lo habitual, '
      'menciónalo aparte, como un ahorro único de este mes (no mensual, '
      'no lo sumes a las opciones de (b)).',
    )
    ..writeln(
      '(d) Cierra diciendo que la decisión de qué hacer con estas '
      'opciones es del usuario, sin más.',
    )
    ..writeln()
    ..writeln(
      'No empieces la respuesta por "la aplicación" ni por ninguna '
      'variante de esa frase, y no describas cómo se ha hecho el cálculo '
      '(nada de "se han calculado", "a partir de tus gastos" o similar): '
      've directo a la frase (a). No repitas la palabra "necesaria" (ya '
      'aparece en la línea de cobertura): para la aportación, di solo '
      '"aportación mensual" o usa el pronombre. No menciones el estado '
      'de la meta (cumplida/en camino/por detrás/vencida): esa '
      'información es solo para que entiendas el contexto, no para '
      'repetirla. No compares ni recalcules ningún importe entre sí '
      '(nada de porcentajes, diferencias o sumas que no estén ya hechas '
      'en las líneas de arriba). Escribe cada importe exactamente como '
      'llega, con su unidad pegada a la cifra (si llega "19,66 €", '
      'escribe "19,66 €", nunca lo separes en "19,66" y "euros" en '
      'frases distintas, ni le añadas ni le quites nada). Texto plano, '
      'sin ningún formato Markdown (nada de asteriscos, almohadillas ni '
      'guiones de lista), sin citar estas instrucciones.',
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
