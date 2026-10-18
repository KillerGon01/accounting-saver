import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/transactions/category.dart';
import '../../domain/transactions/llm_gateway.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../../domain/transactions/raw_parsed_transaction.dart';
import '../common/app_check_error.dart';
import '../common/gemini_model_fallback.dart';
import '../common/gemini_transient_retry.dart';

/// [LlmGateway] implementation with Firebase AI Logic's Gemini
/// Developer API backend (not Vertex AI, to stay on the free tier).
/// Models available on the free tier, with fallback between them if
/// one exhausts its quota: see [geminiModelFallbacks].
class GeminiLlmGateway implements LlmGateway {
  GeminiLlmGateway({GeminiModelAvailability? availability})
    : _availability = availability ?? GeminiModelAvailability();

  final GeminiModelAvailability _availability;

  static GenerativeModel _buildModel(String model) {
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        // Lowering the "thinking" level to `low` was tried to reduce
        // latency, but no improvement showed up (the bottleneck isn't
        // reasoning) and correctness did get worse: Gemini's
        // documentation asks for the default level or higher for
        // tasks with calculation (percentages, sums), and with `low`
        // it went as far as interpreting "un 2% de 1000" as 2 instead
        // of 20. The default level (`medium`) is kept, with no
        // `thinkingConfig` set.
        //
        // Temperature at 0: this is data extraction, not drafting. We
        // don't want creativity, but the most literal and repeatable
        // reading of the text.
        temperature: 0,
        responseSchema: Schema.object(
          properties: {
            'understood': Schema.boolean(
              description: 'true si la frase describe con claridad un '
                  'movimiento con un importe. false si no hay ningún '
                  'importe claro en la frase; en ese caso, no incluyas '
                  'ningún otro campo (o déjalos en null).',
            ),
            'amountCents': Schema.integer(
              description: 'Importe en céntimos de euro. Negativo si es un '
                  'gasto, positivo si es un ingreso. Nunca cero. Solo si '
                  'understood es true.',
              nullable: true,
            ),
            'date': Schema.string(
              description: 'Fecha del movimiento en formato ISO 8601 '
                  '(AAAA-MM-DD). Solo si understood es true.',
              nullable: true,
            ),
            'description': Schema.string(
              description: 'Concepto breve del movimiento, por ejemplo '
                  '"Bar con Marta". Solo si understood es true.',
              nullable: true,
            ),
            'category': Schema.enumString(
              enumValues: [for (final category in Category.values) category.name],
              description: 'Categoría del movimiento. Solo si understood es '
                  'true.',
              nullable: true,
            ),
          },
          optionalProperties: ['amountCents', 'date', 'description', 'category'],
        ),
      ),
    );
  }

  @override
  Future<RawParsedTransaction> extractTransaction({
    required String text,
    required DateTime now,
  }) async {
    final prompt = _buildPrompt(text: text, now: now);

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
        message: 'Se ha agotado la cuota gratuita de la IA por ahora. '
            'Inténtalo más tarde o añade el movimiento a mano.',
      );
    } on TimeoutException {
      // Same as in `GeminiChatGateway._generate`: the initial attempt
      // and `withTransientRetry`'s single retry have already been
      // used up, each with its own `geminiRequestTimeout`.
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
      throw LlmGatewayException(
        'service-error',
        message: 'No se pudo generar el movimiento con la IA: ${error.message}',
      );
    } catch (error) {
      // Network failures (no connection, timeout, etc.) arrive as
      // exceptions from the HTTP client, not from firebase_ai.
      throw const LlmGatewayException(
        'network-error',
        message: 'No se pudo contactar con la IA. Comprueba tu conexión e '
            'inténtalo de nuevo.',
      );
    }

    if (responseText == null) {
      throw const LlmGatewayException(
        'malformed-response',
        message: 'La IA no ha devuelto ningún resultado. Inténtalo de nuevo '
            'o añade el movimiento a mano.',
      );
    }

    return _parse(responseText);
  }

  RawParsedTransaction _parse(String jsonText) {
    try {
      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      final understood = json['understood'] as bool? ?? false;
      if (!understood) {
        return const RawParsedTransaction(understood: false);
      }

      final dateText = json['date'] as String?;
      return RawParsedTransaction(
        understood: true,
        amountCents: (json['amountCents'] as num?)?.toInt(),
        date: dateText == null ? null : _truncateToDate(DateTime.parse(dateText)),
        description: json['description'] as String?,
        categoryName: json['category'] as String?,
      );
    } catch (error) {
      throw const LlmGatewayException(
        'malformed-response',
        message: 'No se pudo interpretar la respuesta de la IA. Inténtalo '
            'de nuevo o añade el movimiento a mano.',
      );
    }
  }

  DateTime _truncateToDate(DateTime date) => DateTime(date.year, date.month, date.day);

  String _buildPrompt({required String text, required DateTime now}) {
    final today = _isoDate(now);
    return '''
Eres un asistente que extrae un único movimiento financiero personal a partir
de una frase en español.
Hoy es $today. Interpreta fechas relativas ("ayer", "el lunes pasado", "hace
tres días") respecto a esa fecha.
El importe debe ser distinto de cero: negativo si es un gasto, positivo si es
un ingreso. No inventes datos que no se puedan deducir de la frase.
Si la frase describe un cálculo sobre una cantidad (un porcentaje, una suma,
una resta...) en vez de dar el importe final directamente, resuelve tú el
cálculo exacto antes de devolver el importe. Por ejemplo: "un 2% de 1000" son
20, no 2; "la mitad de 50" son 25, no 50.

Si la frase NO contiene un importe claro, o depende de un dato que no está en
la propia frase (por ejemplo, un porcentaje sobre una cantidad que no se
menciona), devuelve understood=false y deja el resto de campos sin indicar.
Nunca inventes ni deduzcas un importe, un concepto o una categoría que no
estén en la frase.

Frase del usuario: "$text"
''';
  }

  String _isoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
