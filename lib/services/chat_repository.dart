import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import 'api_service.dart';
import 'socket_service.dart';

class ChatRepository {
  static final ChatRepository _instance = ChatRepository._internal();
  factory ChatRepository() => _instance;
  ChatRepository._internal();

  // Simple memory cache for chat history
  static final Map<String, List<ChatMessage>> _chatCache = {};

  Future<List<ChatMessage>> getChatHistory({
    required String myPhone,
    required String otherPhone,
    int page = 1,
    int limit = 30,
  }) async {
    final String cacheKey = '${myPhone}_$otherPhone';
    
    // Return cached data for page 1 for instant loading
    if (page == 1 && _chatCache.containsKey(cacheKey)) {
      _fetchAndCacheHistory(myPhone, otherPhone, cacheKey, limit); // Background refresh
      return _chatCache[cacheKey]!;
    }

    return await _fetchAndCacheHistory(myPhone, otherPhone, cacheKey, limit, page: page);
  }

  Future<List<ChatMessage>> _fetchAndCacheHistory(String myPhone, String otherPhone, String cacheKey, int limit, {int page = 1}) async {
    try {
      final response = await ApiService.get('/api/admin/chat-history/$myPhone/$otherPhone?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(response.body);
        final messages = history.map((m) => ChatMessage.fromJson(m, myPhone)).toList();
        
        if (page == 1) {
          _chatCache[cacheKey] = messages;
        }
        return messages;
      }
      return [];
    } catch (e) {
      debugPrint("Chat history error: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getInbox(String phone, {int page = 1, int limit = 20}) async {
    try {
      final response = await ApiService.get('/api/chat/inbox/$phone?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'chats': [], 'totalUnread': 0};
    } catch (e) {
      debugPrint("Inbox fetch error: $e");
      return {'chats': [], 'totalUnread': 0};
    }
  }

  Future<Map<String, dynamic>> checkBlockStatus(String myPhone, String otherPhone) async {
    try {
      final response = await ApiService.get('/api/chat/check-block/$myPhone/$otherPhone');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'isBlocked': data['isBlocked'] ?? false,
          'blockerPhone': data['blockerPhone']
        };
      }
      return {'isBlocked': false, 'blockerPhone': null};
    } catch (e) {
      return {'isBlocked': false, 'blockerPhone': null};
    }
  }

  void blockUser({required String blockerPhone, required String blockedPhone, String reason = "No reason", bool isReported = false}) {
    SocketService().emit('block_user', {
      'blockerPhone': blockerPhone,
      'blockedPhone': blockedPhone,
      'reason': reason,
      'isReported': isReported
    });
  }

  void unblockUser({required String blockerPhone, required String blockedPhone}) {
    SocketService().emit('unblock_user', {
      'blockerPhone': blockerPhone,
      'blockedPhone': blockedPhone
    });
  }

  Future<String?> uploadMedia(File file, String phone, String type) async {
    try {
      var response = await ApiService.multipart('/api/chat/upload', file.path, 'image', {'phone': phone});
      if (response.statusCode == 200) {
        var res = await http.Response.fromStream(response);
        return jsonDecode(res.body)['imageUrl'];
      }
      return null;
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
    }
  }

  void sendMessage({
    required String senderPhone,
    required String receiverPhone,
    required String senderName,
    required String message,
    String type = 'text',
    String? localId,
    String? imageUrl,
    String? audioUrl,
    bool isViewOnce = false,
    String? replyToId,
    String? replyText,
    String? replyType,
    Function(dynamic)? ack,
  }) {
    SocketService().emit('send_message', {
      'localId': localId,
      'senderPhone': senderPhone,
      'receiverPhone': receiverPhone,
      'senderName': senderName,
      'message': message,
      'type': type,
      'imageUrl': imageUrl,
      'audioUrl': audioUrl,
      'isViewOnce': isViewOnce,
      'replyToId': replyToId,
      'replyText': replyText,
      'replyType': replyType,
    }, ack);
  }

  void markOpened(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('mark_opened', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
  }

  void markChatSeen(String myPhone, String otherPhone) {
    SocketService().emit('mark_chat_seen', {'myPhone': myPhone, 'otherPhone': otherPhone});
  }

  void deleteMessageForEveryone(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('delete_message_for_everyone', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
  }

  void deleteMessageForMe(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('delete_message', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
  }

  void editMessage(String messageId, String newText, String myPhone, String otherPhone) {
    SocketService().emit('edit_message', {
      'messageId': messageId,
      'newText': newText,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
  }

  Future<bool> updateConversationMetadata({
    required String myPhone,
    required String otherPhone,
    bool? isMuted,
    bool? isFavourite,
    bool? isHidden,
  }) async {
    try {
      final response = await ApiService.post('/api/chat/update-metadata', {
        'phone': myPhone,
        'partnerPhone': otherPhone,
        if (isMuted != null) 'isMuted': isMuted,
        if (isFavourite != null) 'isFavourite': isFavourite,
        if (isHidden != null) 'isHidden': isHidden,
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Update metadata error: $e");
      return false;
    }
  }

  Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        final List<dynamic> photos = jsonDecode(res.body)['photos'] ?? [];
        // Secure URLs
        for (var p in photos) {
          p['imageUrl'] = ApiService.getSecureUrl(p['imageUrl']);
        }
        return photos;
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }

  Future<bool> deleteRecentPhoto(String phone, String imageUrl) async {
    try {
      // Strip token before sending to delete API to match DB record
      final String cleanUrl = imageUrl.split('?')[0];
      
      final response = await ApiService.post('/api/chat/delete-recent-photo', {
        'phone': phone,
        'imageUrl': cleanUrl
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Delete photo error: $e");
      return false;
    }
  }

  static void clearChatCache(String myPhone, String otherPhone) {
    _chatCache.remove('${myPhone}_$otherPhone');
  }
}
