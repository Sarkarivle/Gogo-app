import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'socket_service.dart';

class ModerationRepository {
  static final ModerationRepository _instance = ModerationRepository._internal();
  factory ModerationRepository() => _instance;
  ModerationRepository._internal();

  Future<bool> reportUser({
    required String reporterPhone,
    required String reportedPhone,
    required String category,
    String? description,
    String reportType = 'General',
  }) async {
    try {
      final response = await ApiService.post('/api/user/report', {
        'reporterPhone': reporterPhone,
        'reportedPhone': reportedPhone,
        'category': category,
        'reportType': reportType,
        'description': description,
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Report error: $e');
      return false;
    }
  }

  void blockUser({
    required String blockerPhone,
    required String blockedPhone,
    String reason = "No reason",
  }) {
    SocketService().emit('block_user', {
      'blockerPhone': blockerPhone,
      'blockedPhone': blockedPhone,
      'reason': reason,
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

  Future<List<dynamic>> getBlockedList(String phone) async {
    try {
      final response = await ApiService.get('/api/chat/blocked-list/$phone');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['blockedUsers'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching blocked list: $e');
      return [];
    }
  }
}
