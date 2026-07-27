import 'dart:convert';
import 'package:gogo/core/api/api_service.dart';

/// Fetches the list of fake-partner video clips played during Random Live
/// matching (see FakeRandomCallScreen). Clips are hosted on the backend
/// (public/video/randomlive/ — see ChatController.getRandomLiveVideos)
/// instead of bundled into the app, so clips can be added/swapped without an
/// app release. Deliberately NOT cached — an admin uploading/removing a clip
/// via the dashboard should take effect on the very next match, not after an
/// app restart. The request itself is a cheap directory listing.
class RandomLiveVideoService {
  static final RandomLiveVideoService _instance = RandomLiveVideoService._internal();
  factory RandomLiveVideoService() => _instance;
  RandomLiveVideoService._internal();

  /// Returns full, playable URLs. Empty list (never null) if the fetch
  /// fails or no clips are configured on the server — callers should treat
  /// that as "no fake video available" and fall back to real matching.
  Future<List<String>> getFakePartnerVideos() async {
    try {
      final response = await ApiService.get('/api/chat/random-live/videos');
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final paths = (data['clips'] as List?)?.cast<String>() ?? [];
      return paths.map((p) => ApiService.getSecureUrl(p)).toList();
    } catch (_) {
      return [];
    }
  }
}
