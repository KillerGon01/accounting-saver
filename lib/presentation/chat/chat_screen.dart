import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat/chat_message.dart';
import '../theme/app_theme.dart';
import 'chat_error_messages.dart';
import 'chat_providers.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final history = List<ChatMessage>.from(_messages);
    final userMessage = ChatMessage(role: ChatRole.user, text: text, sentAt: DateTime.now());

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final reply = await ref.read(sendChatMessageProvider)(
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
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
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
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                        enabled: !_isSending,
                        maxLength: ChatScreen.maxLength,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '¿Cuánto he gastado este mes?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    IconButton.filled(
                      tooltip: 'Enviar',
                      onPressed: _isSending ? null : _send,
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
