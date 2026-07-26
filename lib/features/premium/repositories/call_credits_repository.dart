import 'dart:convert';
import 'package:gogo/core/api/api_service.dart';

/// Call credits are a separate currency from Premium — spent one at a time
/// on each fake-call attempt to a creator. See ChatController.checkCallCredit
/// (vps_code/src/features/chat/controllers/ChatController.js) for the
/// server-side, race-safe deduction.
class CallCreditsRepository {
  static final CallCreditsRepository _instance = CallCreditsRepository._internal();
  factory CallCreditsRepository() => _instance;
  CallCreditsRepository._internal();

  /// Atomically spends one call credit for a call attempt to [creatorPhone].
  /// Returns true if the call should proceed (a credit was spent), false if
  /// the user has none left — the caller should then show
  /// [BuyCallCreditsScreen] instead of attempting the call.
  Future<bool> checkAndConsumeCredit(String creatorPhone) async {
    try {
      final response = await ApiService.post('/api/chat/call/check-credit', {
        'creatorPhone': creatorPhone,
      });
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['success'] == true && data['allowed'] == true;
    } catch (_) {
      return false;
    }
  }
}
