import 'dart:async';

import 'package:accounting_saver/domain/chat/chat_gateway.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';

/// Configurable fake for testing [SendChatMessage] without calling
/// Gemini.
///
/// - `FakeChatGateway.returning(...)` returns a fixed text without
///   calling any function.
/// - `FakeChatGateway.callingFunction(...)` simulates the model
///   requesting a function before responding, to check the executor
///   is called with the expected name and arguments.
/// - `FakeChatGateway.throwing(...)` simulates a gateway error.
/// - `FakeChatGateway.pending()` doesn't respond until [complete] or
///   [completeWithError] is called: to test in the UI what's shown
///   while a request is still in flight (progress indicator,
///   disabled send button...) without waiting real time.
class FakeChatGateway implements ChatGateway {
  FakeChatGateway.returning(this._result)
    : _error = null,
      _functionName = null,
      _functionArguments = null,
      _pending = null;

  FakeChatGateway.callingFunction(this._functionName, this._functionArguments, this._result)
    : _error = null,
      _pending = null;

  FakeChatGateway.throwing(Object error)
    : _error = error,
      _result = null,
      _functionName = null,
      _functionArguments = null,
      _pending = null;

  FakeChatGateway.pending()
    : _error = null,
      _result = null,
      _functionName = null,
      _functionArguments = null,
      _pending = Completer<String>();

  final String? _result;
  final Object? _error;
  final String? _functionName;
  final Map<String, Object?>? _functionArguments;
  final Completer<String>? _pending;

  List<ChatMessage>? lastHistory;
  String? lastMessage;
  Map<String, Object?>? lastFunctionResult;
  int callCount = 0;

  void complete(String result) => _pending!.complete(result);

  void completeWithError(Object error) => _pending!.completeError(error);

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  }) async {
    callCount++;
    lastHistory = history;
    lastMessage = message;
    if (_pending != null) return _pending.future;
    if (_error != null) throw _error;

    if (_functionName != null) {
      lastFunctionResult = await executeFunction(_functionName, _functionArguments ?? {});
    }
    return _result!;
  }
}
