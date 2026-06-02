import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

enum MessageStatus { sending, sent, delivered, seen, error }

class ChatMessage {
  String? id;
  final String? localId; // For optimistic UI
  String? text;
  String? imageUrl;
  String? audioUrl;
  String? localFilePath; // For optimistic UI media
  String type; // 'text', 'image', 'audio', 'block_event', 'unblock_event'
  final bool isViewOnce;
  bool isOpened;
  bool isDeletedForEveryone;
  final bool isMe;
  final DateTime timestamp;
  bool isEdited;
  MessageStatus status;
  bool isNew; // For intro animation

  // Compatibility getters
  bool get isDelivered => status == MessageStatus.delivered || status == MessageStatus.seen;
  bool get isSeen => status == MessageStatus.seen;

  // Reply features
  final String? replyToId;
  final String? replyText;
  final String? replyType;

  // Call metadata
  final Map<String, dynamic>? metadata;

  ChatMessage({
    this.id,
    this.localId,
    this.text,
    this.imageUrl,
    this.audioUrl,
    this.localFilePath,
    this.type = 'text',
    this.isViewOnce = false,
    this.isOpened = false,
    this.isDeletedForEveryone = false,
    required this.isMe,
    required this.timestamp,
    this.isEdited = false,
    this.status = MessageStatus.sent,
    this.isNew = false,
    this.replyToId,
    this.replyText,
    this.replyType,
    this.metadata,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myPhone) {
    final sPhone = PhoneUtils.normalize(json['senderPhone']?.toString());
    final mPhone = PhoneUtils.normalize(myPhone);
    
    return ChatMessage(
      id: (json['_id'] ?? json['id'] ?? json['messageId'])?.toString(),
      localId: json['localId']?.toString(),
      text: json['message'],
      imageUrl: json['imageUrl'] != null ? ApiService.getSecureUrl(json['imageUrl']) : null,
      audioUrl: json['audioUrl'] != null ? ApiService.getSecureUrl(json['audioUrl']) : null,
      type: json['type'] ?? 'text',
      isViewOnce: json['isViewOnce'] ?? false,
      isOpened: json['isOpened'] ?? false,
      isDeletedForEveryone: json['isDeletedForEveryone'] ?? false,
      isMe: sPhone == mPhone && mPhone != null,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()).toLocal(),
      isEdited: json['isEdited'] ?? false,
      status: (json['isOpened'] == true) 
          ? MessageStatus.seen 
          : (json['isDelivered'] == true ? MessageStatus.delivered : MessageStatus.sent),
      replyToId: json['replyToId'],
      replyText: json['replyText'],
      replyType: json['replyType'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'localId': localId,
      'message': text,
      'imageUrl': imageUrl,
      'audioUrl': audioUrl,
      'type': type,
      'isViewOnce': isViewOnce,
      'isOpened': isOpened,
      'isDeletedForEveryone': isDeletedForEveryone,
      'timestamp': timestamp.toIso8601String(),
      'replyToId': replyToId,
      'replyText': replyText,
      'replyType': replyType,
    };
  }
}
