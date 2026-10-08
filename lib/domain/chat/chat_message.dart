enum ChatRole { user, assistant }

/// Mensaje de la conversación de chat. Vive solo en memoria: nunca se
/// guarda en Firestore ni se registra en logs.
class ChatMessage {
  const ChatMessage({required this.role, required this.text, required this.sentAt});

  final ChatRole role;
  final String text;
  final DateTime sentAt;
}
