import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

class ModerationRepository {
  static final ModerationRepository _instance = ModerationRepository._internal();
  factory ModerationRepository() => _instance;
  ModerationRepository._internal();

  // phone -> isBlocked
  final ValueNotifier<Map<String, bool>> blockStatusNotifier = ValueNotifier({});

  void init() {
    SocketService().eventStream.listen((event) {
      if (event['event'] == 'moderation_state_updated') {
        final data = event['data'];
        final String? blocker = PhoneUtils.normalize(data['blockerPhone']?.toString());
        final String? blocked = PhoneUtils.normalize(data['blockedPhone']?.toString());
        final bool isBlocked = data['isBlocked'] ?? false;
        
        final currentUser = UserRepository().currentUser;
        if (currentUser == null) return;
        final myPhone = PhoneUtils.normalize(currentUser['phone']);
        
        if (blocker == null || blocked == null || myPhone == null) return;

        // Determine who is the "other" person in this block event relative to me
        String? otherPhone;
        if (blocker == myPhone) {
          otherPhone = blocked;
        } else if (blocked == myPhone) {
          otherPhone = blocker;
        }

        if (otherPhone != null) {
          final updated = Map<String, bool>.from(blockStatusNotifier.value);
          updated[otherPhone] = isBlocked;
          blockStatusNotifier.value = updated;
          debugPrint("🚫 [MODERATION] Real-time block update for $otherPhone: $isBlocked");
        }
      }
    });
  }

  bool isBlocked(String phone) {
    final normalized = PhoneUtils.normalize(phone);
    return blockStatusNotifier.value[normalized] ?? false;
  }

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
    final String? normalizedOther = PhoneUtils.normalize(blockedPhone);
    if (normalizedOther != null) {
      final updated = Map<String, bool>.from(blockStatusNotifier.value);
      updated[normalizedOther] = true;
      blockStatusNotifier.value = updated;
    }

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
    final String? normalizedOther = PhoneUtils.normalize(blockedPhone);
    if (normalizedOther != null) {
      final updated = Map<String, bool>.from(blockStatusNotifier.value);
      updated[normalizedOther] = false;
      blockStatusNotifier.value = updated;
    }

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
