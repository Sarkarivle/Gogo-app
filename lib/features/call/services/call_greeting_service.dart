import 'dart:convert';
import 'package:gogo/core/api/api_service.dart';

/// Fetches the list of pre-recorded "hello" greeting clips played during a
/// simulated call preview (see FakeCallScreen). Clips are hosted on the
/// backend (public/audio/greetings/ — see ChatController.getCallGreetingAudio)
/// instead of bundled into the app, so new voices can be added/swapped
/// without an app release. Deliberately NOT cached — an admin uploading a
/// new clip (or deleting one) via the dashboard should take effect on the
/// very next call, not after an app restart. The request itself is a cheap
/// directory listing, so re-fetching every call is negligible.
class CallGreetingService {
  static final CallGreetingService _instance = CallGreetingService._internal();
  factory CallGreetingService() => _instance;
  CallGreetingService._internal();

  /// Returns full, playable URLs. Empty list (never null) if the fetch
  /// fails or no clips are configured on the server — callers should treat
  /// that as "no greeting audio available" rather than an error.
  Future<List<String>> getGreetingClips() async {
    try {
      final response = await ApiService.get('/api/chat/call/greeting-audio');
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final paths = (data['clips'] as List?)?.cast<String>() ?? [];
      return paths.map((p) => ApiService.getSecureUrl(p)).toList();
    } catch (_) {
      return [];
    }
  }
}
