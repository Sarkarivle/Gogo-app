import 'dart:async';
 import 'package:flutter/widgets.dart';
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

  /// Returns a stream of events filtered specifically for a room.
  /// This is massive for performance as the UI won't even wake up for other room events.
  Stream<Map<String, dynamic>> getRoomStream(String roomId) {
    return chatUpdateStream.where((event) {
      final data = event['data'];
      if (data is Map) {
        // Room ID match
        if (data['roomId'] == roomId) return true;
        
        // Fallback for events that use phones instead of roomId
        final String? sPhone = PhoneUtils.normalize(data['senderPhone']);
        final String? rPhone = PhoneUtils.normalize(data['receiverPhone']);
        if (sPhone != null && rPhone != null) {
          final parts = roomId.split('_');
          return parts.contains(sPhone) && parts.contains(rPhone);
        }
      }
      // Global events like message_deleted might not have roomId, let them through
      return event['event'] == 'message_deleted_for_everyone' || 
             event['event'] == 'moderation_state_updated' ||
             event['event'] == 'global_delivery_update' ||
             event['event'] == 'pending_messages_delivered' ||
             event['event'] == 'chat_seen_update' ||
             event['event'] == 'message_opened';
    });
  }

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
       (type == 'message_deleted' && (data['isDeletedForEveryone'] == true || data['isEveryone'] == true))) {
      final String? messageId = data['messageId'] ?? data['id'];
      final String? roomId = data['roomId'];
      
      if (messageId != null && roomId != null) {
        final parts = roomId.split('_');
        if (parts.length == 2) {
          ChatRepository().updateMessageDeletionInCache(parts[0], parts[1], messageId);
        }
      } else {
        final String? sender = PhoneUtils.normalize(data['senderPhone'] ?? data['myPhone']);
        final String? receiver = PhoneUtils.normalize(data['receiverPhone'] ?? data['otherPhone']);
        if (messageId != null && sender != null && receiver != null) {
          ChatRepository().updateMessageDeletionInCache(sender, receiver, messageId);
        }
      }
    }
 else if (type == 'message_opened') {
      final String? messageId = data['messageId'] ?? data['id'];
      final String? myPhone = SocketService().currentUserPhone;
      
      if (messageId != null && myPhone != null) {
        final String? sPhone = PhoneUtils.normalize(data['senderPhone']);
        final String? rPhone = PhoneUtils.normalize(data['receiverPhone']);
        final String? otherPhone = sPhone == myPhone ? rPhone : sPhone;
        
        if (otherPhone != null) {
          ChatRepository().updateMessageOpenedInCache(myPhone, otherPhone, messageId);
        }
      }
    }
 else if (type == 'receive_message') {
      final String? myPhone = SocketService().currentUserPhone;
      
      // 1-Message Trial Logic: Use up trial on ANY incoming message
      PremiumService().useOneMessageTrial();

      if (myPhone != null) {
        final String? sPhone = PhoneUtils.normalize(data['senderPhone']);
        final String? rPhone = PhoneUtils.normalize(data['receiverPhone']);
        
        // --- REAL-TIME STATUS LOGIC ---
        // If I am the receiver of this message
        if (rPhone == myPhone && sPhone != null) {
          final String? mId = data['_id'] ?? data['id'] ?? data['messageId'];
          final String? localId = data['localId'];
          
          if (mId != null) {
            final state = WidgetsBinding.instance.lifecycleState;
            final bool isAppResumed = state == null || state == AppLifecycleState.resumed;
            
            // Flexible Room Check: Ensure both phones belong to the active room
            final String? activeRoom = SocketService().activeRoomId;
            bool isUserInRoom = false;
            if (activeRoom != null) {
              final parts = activeRoom.split('_');
              isUserInRoom = parts.contains(sPhone) && parts.contains(rPhone);
            }

            if (isAppResumed && isUserInRoom) {
              if (data['isViewOnce'] != true) {
                // Mark as SEEN (Green Tick)
                ChatRepository().markOpened(mId, myPhone, sPhone);
                // Also mark whole chat seen for safety
                ChatRepository().markChatSeen(myPhone, sPhone);
              }
            } else {
              // Otherwise Mark as DELIVERED (Double Grey Tick)
              ChatRepository().markDelivered(mId, myPhone, sPhone, localId: localId);
            }
          }
        }

        final String? otherPhone = sPhone == myPhone ? rPhone : sPhone;
        if (otherPhone != null) {
           final newMessage = ChatMessage.fromJson(Map<String, dynamic>.from(data), myPhone);
           ChatRepository().updateCacheWithNewMessage(myPhone, otherPhone, newMessage);
        }
      }
    }
  }

  void dispose() {
    _chatUpdateController.close();
    _isInitialized = false;
  }
}
