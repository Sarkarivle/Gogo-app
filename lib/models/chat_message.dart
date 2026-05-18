class ChatMessage {
  final String? id;
  String? text;
  final String? imageUrl;
  final String? audioUrl;
  final String type; // 'text', 'image', 'audio', 'block_event', 'unblock_event'
  final bool isViewOnce;
  bool isOpened;
  final bool isMe;
  final DateTime timestamp;
  bool isEdited;

  ChatMessage({
    this.id,
    this.text,
    this.imageUrl,
    this.audioUrl,
    this.type = 'text',
    this.isViewOnce = false,
    this.isOpened = false,
    required this.isMe,
    required this.timestamp,
    this.isEdited = false,
  });
}
