import '../transactions/llm_gateway_exception.dart';
import 'chat_message.dart';

/// Runs a function requested by the model and returns its result as a
/// JSON map. The arguments come from the model and aren't trustworthy:
/// whoever implements this executor validates each one before touching
/// any data, and if one is invalid, runs nothing and returns a map with
/// an `error` key instead of throwing, so the model itself can explain
/// the error to the user.
typedef ChatFunctionExecutor =
    Future<Map<String, Object?>> Function(String name, Map<String, Object?> arguments);

/// Port to a conversational language model with function calling over
/// the user's transactions. The infrastructure layer (Gemini) implements
/// this interface; the domain and application layers don't know the
/// provider.
abstract class ChatGateway {
  /// Sends [message] together with recent history ([history]; the
  /// caller decides how many messages to include). If the model asks to
  /// run a function, [executeFunction] is called with its name and
  /// arguments, and its result is returned to the model; this repeats
  /// until the model produces a final text response, which is what this
  /// method returns.
  ///
  /// Throws [LlmGatewayException] if the AI isn't available (quota,
  /// network) or if it chains too many function calls without
  /// answering.
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  });
}
