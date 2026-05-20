import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ProfileRepository {
  static final Map<String, List<dynamic>> _cache = {};
  static final Map<String, int> _cachePage = {};

  static List<dynamic>? getCachedProfiles(String tab) => _cache[tab];

  static Future<List<dynamic>> getDiscoverProfiles({
    required String myPhone,
    int page = 1,
    int limit = 20,
    String tab = 'Nearby',
    String? distance,
    String? age,
    bool isOnlineOnly = false,
    String? havePlace,
    String? position,
    double? lat,
    double? lng,
  }) async {
    try {
      final queryParams = {
        'phone': myPhone,
        'page': page.toString(),
        'limit': limit.toString(),
        'tab': tab,
        if (distance != null && distance != 'Any') 'distance': distance,
        if (age != null && age != 'Any') 'age': age,
        'isOnlineOnly': isOnlineOnly.toString(),
        if (havePlace != null && havePlace != 'Any') 'havePlace': havePlace,
        if (position != null && position != 'Any') 'position': position,
        if (lat != null && lat != 0) 'lat': lat.toString(),
        if (lng != null && lng != 0) 'lng': lng.toString(),
      };

      final uri = Uri.parse('${ApiService.baseUrl}/api/user/discover').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> users = data['users'] ?? [];
          
          // Only cache page 1 for quick next-time render
          if (page == 1 && users.isNotEmpty) {
            _cache[tab] = users;
          }
          return users;
        }
      }
      return [];
    } catch (e) {
      print('Error in getDiscoverProfiles: $e');
      return [];
    }
  }

  static void clearCache() {
    _cache.clear();
    _cachePage.clear();
  }
}
