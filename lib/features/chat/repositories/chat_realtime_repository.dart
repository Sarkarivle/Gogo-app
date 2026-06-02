import 'dart:async';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';
import 'package:gogo/features/chat/models/chat_message.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';

class ChatRealtimeRepository {
  static final ChatRealtimeRepository _instance = ChatRealtimeRepository._internal();
  factory ChatRealtimeRepository() => _instance;
  ChatRealtimeRepository._internal();

  final StreamController<Map<String, dynamic>> _chatUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatUpdateStream => _chatUpdateController.stream;

  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    SocketService().eventStream.listen((event) {
      final String? type = event['event'];
      final dynamic data = event['data'];
      if (data == null) return;

      // Centralized cache updates for persistence
      _handleGlobalSync(type, data);

      // Broadcast to active UI listeners
      _chatUpdateController.add(event);
    });
  }

  void _handleGlobalSync(String? type, dynamic data) {
    if (data is! Map) return;

    if (type == 'message_deleted_for_everyone' || 
       (type == 'message_deleted' && data['isEveryone'] == true)) {
      final String? messageId = data['messageId'] ?? data['id'];
      final String? sender = PhoneUtils.normalize(data['senderPhone'] ?? data['myPhone']);
      final String? receiver = PhoneUtils.normalize(data['receiverPhone'] ?? data['otherPhone']);
      
      if (messageId != null && sender != null && receiver != null) {
        ChatRepository().updateMessageDeletionInCache(sender, receiver, messageId);
      }
    } else if (type == 'receive_message') {
      final String? myPhone = SocketService().currentUserPhone;
      
      // 1-Message Trial Logic: Use up trial on ANY incoming message
      PremiumService().useOneMessageTrial();

      if (myPhone != null) {
        final String? otherPhone = PhoneUtils.normalize(data['senderPhone'] == myPhone ? data['receiverPhone'] : data['senderPhone']);
        if (otherPhone != null) {
           final newMessage = ChatMessage.fromJson(Map<String, dynamic>.from(data), myPhone);
           ChatRepository().updateCacheWithNewMessage(myPhone, otherPhone, newMessage);
        }
      }
    }
  }

  void dispose() {
    _chatUpdateController.close();
  }
}
