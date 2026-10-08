import '../transactions/llm_gateway_exception.dart';
import 'chat_message.dart';

/// Ejecuta una función pedida por el modelo y devuelve su resultado como
/// mapa JSON. Los argumentos vienen del modelo y no son de fiar: quien
/// implemente este executor valida cada uno antes de tocar ningún dato y,
/// si alguno es inválido, no ejecuta nada y devuelve un mapa con la clave
/// `error` en vez de lanzar una excepción, para que el error se lo pueda
/// explicar el propio modelo al usuario.
typedef ChatFunctionExecutor =
    Future<Map<String, Object?>> Function(String name, Map<String, Object?> arguments);

/// Puerto hacia un modelo de lenguaje conversacional con function calling
/// sobre los movimientos del usuario. La infraestructura (Gemini) implementa
/// esta interfaz; el dominio y la aplicación no conocen el proveedor.
abstract class ChatGateway {
  /// Envía [message] junto con el historial reciente ([history]; quien llama
  /// decide cuántos mensajes incluir). Si el modelo pide ejecutar una
  /// función, se llama a [executeFunction] con su nombre y argumentos, y su
  /// resultado se devuelve al modelo; esto se repite hasta que el modelo
  /// produce una respuesta de texto final, que es lo que devuelve este
  /// método.
  ///
  /// Lanza [LlmGatewayException] si la IA no está disponible (cuota, red) o
  /// si encadena demasiadas llamadas a función sin responder.
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  });
}
