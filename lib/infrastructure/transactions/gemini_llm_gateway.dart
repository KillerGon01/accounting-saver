import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/transactions/category.dart';
import '../../domain/transactions/llm_gateway.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import '../../domain/transactions/raw_parsed_transaction.dart';
import '../common/app_check_error.dart';
import '../common/gemini_model_fallback.dart';
import '../common/gemini_transient_retry.dart';

/// Implementación de [LlmGateway] con el backend Gemini Developer API de
/// Firebase AI Logic (no Vertex AI, para mantenerse en el nivel gratuito).
/// Modelos disponibles en el nivel gratuito, con fallback entre ellos si
/// alguno agota su cuota: ver [geminiModelFallbacks].
class GeminiLlmGateway implements LlmGateway {
  GeminiLlmGateway({GeminiModelAvailability? availability})
    : _availability = availability ?? GeminiModelAvailability();

  final GeminiModelAvailability _availability;

  static GenerativeModel _buildModel(String model) {
    return FirebaseAI.googleAI().generativeModel(
      model: model,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        // Se probó a bajar el nivel de "pensamiento" a `low` para reducir la
        // latencia, pero no se notó mejora (el cuello de botella no es el
        // razonamiento) y sí empeoró la corrección: la documentación de
        // Gemini pide el nivel por defecto o superior para tareas con
        // cálculo (porcentajes, sumas), y con `low` llegó a interpretar
        // "un 2% de 1000" como 2 en vez de 20. Se deja el nivel por defecto
        // (`medium`), sin fijar `thinkingConfig`.
        //
        // Temperatura a 0: esto es extracción de datos, no redacción. No
        // queremos creatividad, sino la lectura más literal y repetible del
        // texto.
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
    } on FirebaseAIException catch (error) {
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
      // Fallos de red (sin conexión, timeout, etc.) llegan como excepciones
      // del cliente HTTP, no de firebase_ai.
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
