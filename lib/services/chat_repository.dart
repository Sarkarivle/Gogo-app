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

  Future<List<ChatMessage>> getChatHistory({
    required String myPhone,
    required String otherPhone,
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final response = await ApiService.get('/api/admin/chat-history/$myPhone/$otherPhone?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(response.body);
        return history.map((m) => ChatMessage.fromJson(m, myPhone)).toList();
        Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
      return [];
    } catch (e) {
      debugPrint("Chat history error: $e");
      return [];
      Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  Future<Map<String, dynamic>> getInbox(String phone, {int page = 1, int limit = 20}) async {
    try {
      final response = await ApiService.get('/api/chat/inbox/$phone?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
        Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
      return {'chats': [], 'totalUnread': 0};
    } catch (e) {
      debugPrint("Inbox fetch error: $e");
      return {'chats': [], 'totalUnread': 0};
      Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  Future<bool> checkBlockStatus(String myPhone, String otherPhone) async {
    try {
      final res1 = await ApiService.get('/api/chat/check-block/$myPhone/$otherPhone');
      final res2 = await ApiService.get('/api/chat/check-block/$otherPhone/$myPhone');
      
      bool iBlocked = jsonDecode(res1.body)['isBlocked'] ?? false;
      bool theyBlocked = jsonDecode(res2.body)['isBlocked'] ?? false;
      
      return iBlocked || theyBlocked;
    } catch (e) {
      return false;
      Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  Future<String?> uploadMedia(File file, String phone, String type) async {
    try {
      var response = await ApiService.multipart('/api/chat/upload', file.path, 'image', {'phone': phone});
      if (response.statusCode == 200) {
        var res = await http.Response.fromStream(response);
        return jsonDecode(res.body)['imageUrl'];
        Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
      return null;
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
      Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
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
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  void markOpened(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('mark_opened', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  void markChatSeen(String myPhone, String otherPhone) {
    SocketService().emit('mark_chat_seen', {'myPhone': myPhone, 'otherPhone': otherPhone});
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  void deleteMessageForEveryone(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('delete_message_for_everyone', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  void deleteMessageForMe(String messageId, String myPhone, String otherPhone) {
    SocketService().emit('delete_message', {
      'messageId': messageId,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}

  void editMessage(String messageId, String newText, String myPhone, String otherPhone) {
    SocketService().emit('edit_message', {
      'messageId': messageId,
      'newText': newText,
      'myPhone': myPhone,
      'otherPhone': otherPhone
    });
    Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
  Future<List<dynamic>> getRecentPhotos(String phone) async {
    try {
      final res = await ApiService.get('/api/chat/recent-photos/$phone');
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['photos'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint("Recent photos error: $e");
      return [];
    }
  }
}
