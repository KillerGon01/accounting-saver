enum ChatRole { user, assistant }

/// Message in the chat conversation. Lives only in memory: never saved
/// to Firestore nor logged.
class ChatMessage {
  const ChatMessage({required this.role, required this.text, required this.sentAt});

  final ChatRole role;
  final String text;
  final DateTime sentAt;
}
