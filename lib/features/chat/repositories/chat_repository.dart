import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gogo/features/chat/models/chat_message.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';

/// Helper for background parsing to keep UI thread 100% smooth
List<ChatMessage> parseMessages(Map<String, dynamic> data) {
  final List<dynamic> history = data['messages'] ?? [];
  final String myPhone = data['myPhone'];
  return history.map((m) => ChatMessage.fromJson(m, myPhone)).toList();
}

class ChatRepository {
  static final ChatRepository _instance = ChatRepository._internal();
  factory ChatRepository() => _instance;
  ChatRepository._internal();

  // Simple memory cache for chat history
  static final Map<String, List<ChatMessage>> _chatCache = {};

  String _getCacheKey(String p1, String p2) {
    final n1 = PhoneUtils.normalize(p1) ?? p1;
    final n2 = PhoneUtils.normalize(p2) ?? p2;
    List<String> phones = [n1, n2];
    phones.sort();
    return phones.join('_');
  }

  Future<Map<String, dynamic>> getChatHistory({
    required String myPhone,
    required String otherPhone,
    int page = 1,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    final String cacheKey = _getCacheKey(myPhone, otherPhone);
    
    // Return cached data for page 1 for instant loading unless forced
    if (page == 1 && _chatCache.containsKey(cacheKey) && !forceRefresh) {
      return {
        'messages': _chatCache[cacheKey]!,
        'isBlocked': false, // Placeholder, will be updated by refresh
        'isPartnerDeactivated': false,
        'hasReviewed': false
      };
    }

    final mPhone = PhoneUtils.normalize(myPhone) ?? myPhone;
    final oPhone = PhoneUtils.normalize(otherPhone) ?? otherPhone;
    final response = await ApiService.get('/api/chat/history/$mPhone/$oPhone?page=$page&limit=$limit');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      
      if (page == 1 && decoded is Map) {
        // Use background isolate for parsing large history batches
        final List<ChatMessage> messages = await compute(parseMessages, {
          'messages': decoded['messages'],
          'myPhone': mPhone
        });
        
        // Ensure Newest First (Sort by timestamp just in case server/reverse logic varies)
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        _chatCache[cacheKey] = messages;
        return {
          'messages': messages,
          'isBlocked': decoded['isBlocked'] ?? false,
          'blockerPhone': decoded['blockerPhone'],
          'isPartnerDeactivated': decoded['isPartnerDeactivated'] ?? false,
          'hasReviewed': decoded['hasReviewed'] ?? false,
        };
      } else if (decoded is List) {
        final List<ChatMessage> messages = await compute(parseMessages, {
          'messages': decoded,
          'myPhone': mPhone
        });
        // Newest first for this batch
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return {'messages': messages};
      }
    }
    return {'messages': []};
  }

  /// Prefetch chat history into memory cache
  void prefetchHistory(String myPhone, String otherPhone) {
    final String cacheKey = _getCacheKey(myPhone, otherPhone);
    if (!_chatCache.containsKey(cacheKey)) {
      getChatHistory(myPhone: myPhone, otherPhone: otherPhone, forceRefresh: true);
    }
  }

  Future<Map<String, dynamic>> getInbox(String phone, {int page = 1, int limit = 20}) async {
    try {
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      final response = await ApiService.get('/api/chat/inbox/$nPhone?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (page == 1 && data['chats'] != null) {
          _saveInboxToCache(nPhone, data);
        }
        return data;
      }
      return {'chats': [], 'totalUnread': 0};
    } catch (e) {
      debugPrint("Inbox fetch error: $e");
      return {'chats': [], 'totalUnread': 0};
    }
  }

  Future<void> _saveInboxToCache(String phone, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_inbox_$phone', jsonEncode(data));
    } catch (e) {
      debugPrint("Cache Save Error: $e");
    }
  }

  Future<Map<String, dynamic>?> getCachedInbox(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      final cached = prefs.getString('cached_inbox_$nPhone');
      if (cached != null) {
        return jsonDecode(cached);
      }
    } catch (e) {
      debugPrint("Cache Load Error: $e");
    }
    return null;
  }

  Future<String?> uploadMedia(File file, String phone, String type) async {
    try {
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      debugPrint("📤 [CHAT_UPLOAD] Starting upload: ${file.path.split('/').last} for $nPhone, type: $type");
      
      if (!file.existsSync()) {
        debugPrint("🚨 [CHAT_UPLOAD] File does not exist at: ${file.path}");
        return null;
      }

      final encodedPhone = Uri.encodeComponent(nPhone);
      final url = '${ApiService.baseUrl}/api/chat/upload?phone=$encodedPhone';
      debugPrint("📡 [CHAT_UPLOAD] URL: $url");

      var request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Get headers from ApiService to ensure consistency
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      request.headers['Accept'] = 'application/json';
      request.headers['x-gogo-secret'] = ApiService.mediaToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      request.fields['phone'] = nPhone;
      request.fields['type'] = type;
      
      // Smart MIME Type detection and extension enforcement
      String mimeType = 'image/jpeg';
      String extension = '.jpg';
      if (type == 'video') {
        mimeType = 'video/mp4';
        extension = '.mp4';
      } else if (type == 'audio') {
        mimeType = 'audio/m4a';
        extension = '.m4a';
      }

      // Generate a clean filename with the correct extension for server-side multer filter
      String fileName = 'upload_${DateTime.now().millisecondsSinceEpoch}$extension';

      request.files.add(await http.MultipartFile.fromPath(
        'image', 
        file.path,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ));
      
      // Increased timeout for videos (2 minutes)
      var streamedResponse = await request.send().timeout(
        Duration(seconds: type == 'video' ? 120 : 45)
      );
      var response = await http.Response.fromStream(streamedResponse);
      
      debugPrint("📡 [CHAT_UPLOAD] Response Status: ${response.statusCode}");
      debugPrint("📡 [CHAT_UPLOAD] Response Body: ${response.body}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['imageUrl'] != null) {
          debugPrint("✅ [CHAT_UPLOAD] Success: ${data['imageUrl']}");
          return data['imageUrl'];
        }
      } else {
        debugPrint("❌ [CHAT_UPLOAD] Server returned ${response.statusCode}");
      }
      return null;
    } catch (e, stack) {
      debugPrint("🚨 [CHAT_UPLOAD] Exception: $e");
      debugPrint("🚨 [CHAT_UPLOAD] Stack: $stack");
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
    // 1-Message Trial Logic: Use up trial on ANY outgoing message
    PremiumService().useOneMessageTrial();

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

  void markDelivered(String messageId, String myPhone, String otherPhone, {String? localId}) {
    SocketService().emit('mark_delivered', {
      'messageId': messageId,
      'localId': localId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
  }

  void markChatSeen(String myPhone, String otherPhone) {
    SocketService().emit('mark_chat_seen', {'myPhone': myPhone, 'otherPhone': otherPhone});
  }

  void deleteMessage(String messageId, {required String deleteType, required String myPhone, required String otherPhone}) {
    if (deleteType == 'everyone') {
      deleteMessageForEveryone(messageId, myPhone, otherPhone);
    } else {
      deleteMessageForMe(messageId, myPhone, otherPhone);
    }
  }

  void deleteMessageForEveryone(String messageId, String myPhone, String otherPhone) {
    final mPhone = PhoneUtils.normalize(myPhone) ?? myPhone;
    final oPhone = PhoneUtils.normalize(otherPhone) ?? otherPhone;
    List<String> phones = [mPhone, oPhone];
    phones.sort();
    final String roomId = phones.join('_');

    SocketService().emit('delete_message_for_everyone', {
      'messageId': messageId,
      'myPhone': mPhone,
      'otherPhone': oPhone,
      'roomId': roomId,
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

  void logCall({
    required String senderPhone,
    required String receiverPhone,
    required String callType,
    required int duration,
    required String status,
  }) {
    SocketService().emit('log_call', {
      'senderPhone': senderPhone,
      'receiverPhone': receiverPhone,
      'callType': callType,
      'duration': duration,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
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
      final mPhone = PhoneUtils.normalize(myPhone) ?? myPhone;
      final oPhone = PhoneUtils.normalize(otherPhone) ?? otherPhone;
      final response = await ApiService.post('/api/chat/update-metadata', {
        'phone': mPhone,
        'partnerPhone': oPhone,
        'isMuted': isMuted,
        'isFavourite': isFavourite,
        'isHidden': isHidden,
      }..removeWhere((key, value) => value == null));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Update metadata error: $e");
      return false;
    }
  }

  Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      final res = await ApiService.get('/api/chat/recent-photos/$nPhone');
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
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      // 1. Strip token if present
      String cleanUrl = imageUrl.split('?')[0];
      
      // 2. Remove base URL to match the relative path stored in DB
      if (cleanUrl.contains(ApiService.baseUrl)) {
        cleanUrl = cleanUrl.replaceAll(ApiService.baseUrl, '');
      }
      
      final response = await ApiService.post('/api/chat/delete-recent-photo', {
        'phone': nPhone,
        'imageUrl': cleanUrl
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Delete photo error: $e");
      return false;
    }
  }

  static void clearChatCache(String myPhone, String otherPhone) {
    final n1 = PhoneUtils.normalize(myPhone) ?? myPhone;
    final n2 = PhoneUtils.normalize(otherPhone) ?? otherPhone;
    List<String> phones = [n1, n2];
    phones.sort();
    _chatCache.remove(phones.join('_'));
  }

  static void clearAllCache() {
    _chatCache.clear();
  }

  /// Update the memory cache with a new message
  void updateCacheWithNewMessage(String myPhone, String otherPhone, ChatMessage message) {
    final String cacheKey = _getCacheKey(myPhone, otherPhone);
    
    if (_chatCache.containsKey(cacheKey)) {
      final List<ChatMessage> cached = _chatCache[cacheKey]!;
      // Avoid duplicates
      if (!cached.any((m) => m.id == message.id || (m.localId != null && m.localId == message.localId))) {
        cached.insert(0, message);
      }
    }
  }

  /// Update a message in the cache when it's opened (Seen)
  void updateMessageOpenedInCache(String myPhone, String otherPhone, String messageId) {
    final String cacheKey = _getCacheKey(myPhone, otherPhone);
    
    if (_chatCache.containsKey(cacheKey)) {
      final List<ChatMessage> cached = _chatCache[cacheKey]!;
      final int index = cached.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        cached[index].status = MessageStatus.seen;
        if (cached[index].isViewOnce) {
           cached[index].isOpened = true;
           cached[index].imageUrl = null;
           cached[index].audioUrl = null;
        }
      }
    }
  }

  /// Update a message in the cache when it's deleted for everyone
  void updateMessageDeletionInCache(String myPhone, String otherPhone, String messageId) {
    final String cacheKey = _getCacheKey(myPhone, otherPhone);
    
    if (_chatCache.containsKey(cacheKey)) {
      final List<ChatMessage> cached = _chatCache[cacheKey]!;
      final int index = cached.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        cached[index].isDeletedForEveryone = true;
        cached[index].text = null;
        cached[index].imageUrl = null;
        cached[index].audioUrl = null;
        cached[index].localFilePath = null;
      }
    }
  }

  void blockUser({
    required String blockerPhone,
    required String blockedPhone,
    String reason = "No reason",
    bool isReported = false,
  }) {
    SocketService().emit('block_user', {
      'blockerPhone': blockerPhone,
      'blockedPhone': blockedPhone,
      'reason': reason,
      'isReported': isReported,
    });
  }

  void unblockUser({
    required String blockerPhone,
    required String blockedPhone,
  }) {
    SocketService().emit('unblock_user', {
      'blockerPhone': blockerPhone,
      'blockedPhone': blockedPhone,
    });
  }

  Future<Map<String, dynamic>> checkBlockStatus(String myPhone, String otherPhone) async {
    try {
      final mPhone = PhoneUtils.normalize(myPhone) ?? myPhone;
      final oPhone = PhoneUtils.normalize(otherPhone) ?? otherPhone;
      final response = await ApiService.get('/api/chat/check-block/$mPhone/$oPhone');
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
}
