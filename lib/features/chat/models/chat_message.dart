import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

enum MessageStatus { sending, sent, delivered, seen, error }

class ChatMessage {
  String? id;
  final String? localId;
  String? text;
  String? imageUrl;
  String? audioUrl;
  String? localFilePath;
  String type;
  final bool isViewOnce;
  
  // Real-time notifiers for high-performance UI updates
  late final ValueNotifier<bool> openedNotifier;
  late final ValueNotifier<bool> deletedForEveryoneNotifier;
  late final ValueNotifier<MessageStatus> statusNotifier;
  late final ValueNotifier<String?> textNotifier;

  final bool isMe;
  final DateTime timestamp;
  bool isEdited;
  bool isNew;

  bool get isOpened => openedNotifier.value;
  set isOpened(bool val) => openedNotifier.value = val;
  
  bool get isDeletedForEveryone => deletedForEveryoneNotifier.value;
  set isDeletedForEveryone(bool val) => deletedForEveryoneNotifier.value = val;

  MessageStatus get status => statusNotifier.value;
  set status(MessageStatus val) {
    if (val.index > statusNotifier.value.index) {
      statusNotifier.value = val;
    }
  }

  // Compatibility getters
  bool get isDelivered => status.index >= MessageStatus.delivered.index;
  bool get isSeen => status == MessageStatus.seen;

  final String? replyToId;
  final String? replyText;
  final String? replyType;
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
    bool isOpened = false,
    bool isDeletedForEveryone = false,
    required this.isMe,
    required this.timestamp,
    this.isEdited = false,
    MessageStatus status = MessageStatus.sent,
    this.isNew = false,
    this.replyToId,
    this.replyText,
    this.replyType,
    this.metadata,
  }) {
    openedNotifier = ValueNotifier(isOpened);
    deletedForEveryoneNotifier = ValueNotifier(isDeletedForEveryone);
    statusNotifier = ValueNotifier(status);
    textNotifier = ValueNotifier(text);
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myPhone) {
    final sPhone = PhoneUtils.normalize(json['senderPhone']?.toString());
    
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
      isMe: sPhone == myPhone,
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

  void dispose() {
    openedNotifier.dispose();
    deletedForEveryoneNotifier.dispose();
    statusNotifier.dispose();
    textNotifier.dispose();
  }
}
