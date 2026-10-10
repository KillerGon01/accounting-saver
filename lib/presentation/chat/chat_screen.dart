import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat/send_chat_message.dart';
import '../../domain/chat/chat_message.dart';
import '../theme/app_theme.dart';
import 'chat_error_messages.dart';
import 'chat_providers.dart';

/// Cuándo se añade cada aviso de progreso mientras se espera la respuesta
/// (ver [_ChatScreenState._send]), sin relación con [geminiRequestTimeout]
/// (90 s): son solo texto para que la espera no parezca colgada, no un
/// límite de tiempo.
const _slowReplyWarningDelay = Duration(seconds: 10);
const _verySlowReplyWarningDelay = Duration(seconds: 45);

/// Chat con la IA sobre los movimientos del usuario (function calling sobre
/// Firestore). La conversación solo vive en esta pantalla, en memoria: no
/// se guarda en Firestore ni se registra en logs, y se pierde al cerrarla.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.userId});

  static const maxLength = 500;

  final String userId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  int? _remainingQuestions;
  Timer? _slowReplyTimer;
  Timer? _verySlowReplyTimer;
  bool _isSlowReply = false;
  bool _isVerySlowReply = false;

  @override
  void initState() {
    super.initState();
    _remainingQuestions = ref.read(sendChatMessageProvider(widget.userId)).remainingQuestions;
  }

  @override
  void dispose() {
    _slowReplyTimer?.cancel();
    _verySlowReplyTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending || (_remainingQuestions ?? 1) <= 0) return;

    final history = List<ChatMessage>.from(_messages);
    final userMessage = ChatMessage(role: ChatRole.user, text: text, sentAt: DateTime.now());

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
      _isSlowReply = false;
      _isVerySlowReply = false;
      _controller.clear();
    });
    _scrollToBottom();

    // Timers, no un `Future.delayed` esperado: no bloquean nada, solo
    // actualizan el texto de progreso si la petición sigue en curso cuando
    // se disparan (de ahí la comprobación de `mounted` y `_isSending` en
    // cada callback, por si ya ha terminado).
    _slowReplyTimer = Timer(_slowReplyWarningDelay, () {
      if (!mounted || !_isSending) return;
      setState(() => _isSlowReply = true);
    });
    _verySlowReplyTimer = Timer(_verySlowReplyWarningDelay, () {
      if (!mounted || !_isSending) return;
      setState(() => _isVerySlowReply = true);
    });

    try {
      final reply = await ref.read(sendChatMessageProvider(widget.userId))(
        userId: widget.userId,
        history: history,
        message: text,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, text: reply, sentAt: DateTime.now()));
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chatErrorMessage(error))));
    } finally {
      _slowReplyTimer?.cancel();
      _verySlowReplyTimer?.cancel();
      final remaining = ref.read(sendChatMessageProvider(widget.userId)).remainingQuestions;
      if (mounted) {
        setState(() {
          _isSending = false;
          _remainingQuestions = remaining;
        });
      }
      _scrollToBottom();
    }
  }

  /// Texto del indicador de progreso mientras se espera la respuesta,
  /// acumulativo: cada aviso se añade al anterior, nunca lo sustituye, así
  /// el usuario sigue viendo "Consultando tus movimientos..." aunque la
  /// espera se alargue.
  String get _progressMessage {
    final parts = ['Consultando tus movimientos...'];
    if (_isSlowReply) parts.add('Esto está tardando más de lo normal...');
    if (_isVerySlowReply) parts.add('Puede tardar hasta un par de minutos.');
    return parts.join(' ');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remainingQuestions ?? SendChatMessage.maxQuestionsPerSession;
    final limitReached = remaining <= 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    limitReached
                        ? 'Has llegado al máximo de preguntas de esta sesión'
                        : 'Te quedan $remaining preguntas',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.m),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _ChatBubble(message: _messages[index]),
                      ),
              ),
              if (_isSending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          _progressMessage,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  0,
                  AppSpacing.m,
                  AppSpacing.m,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_isSending && !limitReached,
                        maxLength: ChatScreen.maxLength,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: limitReached
                              ? 'Has llegado al máximo de preguntas de esta sesión'
                              : '¿Cuánto he gastado este mes?',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    IconButton.filled(
                      tooltip: 'Enviar',
                      onPressed: (_isSending || limitReached) ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.m),
            Text(
              'Pregúntame sobre tus movimientos',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Por ejemplo: "¿Cuánto gasté en restaurantes en octubre?"',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final background = isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh;
    final foreground = isUser ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message.text, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
      ),
    );
  }
}
