import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';

/// Helper for background parsing to keep UI thread smooth during discovery
List<dynamic> parseProfiles(String responseBody) {
  final data = jsonDecode(responseBody);
  if (data['success'] == true) {
    final List<dynamic> users = data['users'] ?? [];
    for (var u in users) {
      if (u is Map && u['profileImages'] != null && u['profileImages'] is List) {
        u['profileImages'] = (u['profileImages'] as List)
            .map((img) => ApiService.getSecureUrl(img.toString()))
            .toList();
      }
    }
    return users;
  }
  return [];
}

class ProfileRepository {
  // Production-grade cache: tab -> List of profiles
  static final Map<String, List<dynamic>> _cache = {};

  // Track last fetch timestamp to avoid duplicate simultaneous requests
  static final Map<String, int> _lastFetchTime = {};

  // Cache TTL: 5 minutes for feed profiles
  static const int _cacheTTL = 5 * 60 * 1000;

  static List<dynamic>? getCachedProfiles(String tab) {
    // Basic cache retrieval
    return _cache[tab];
  }

  static Future<List<dynamic>> getDiscoverProfiles({
    required String myPhone,
    int page = 1,
    int limit = 10,
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
      final now = DateTime.now().millisecondsSinceEpoch;

      // If requesting first page, check if we have a fresh cache
      if (page == 1 && _cache.containsKey(tab)) {
        final lastFetch = _lastFetchTime[tab] ?? 0;
        if (now - lastFetch < _cacheTTL && _cache[tab]!.isNotEmpty) {
          // Return cached data for page 1 if it's fresh enough
          // We still might want to trigger a background refresh in some architectures,
          // but for simple caching, this is effective.
          return _cache[tab]!;
        }
      }

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

      // Use ApiService instead of direct http to include security headers automatically
      final endpoint = uri.toString().replaceFirst(ApiService.baseUrl, '');
      final response = await ApiService.get(endpoint);

      if (response.statusCode == 200) {
        // Optimization: Use Isolate for parsing large discovery batches
        final List<dynamic> users = await compute(parseProfiles, response.body);

        if (page == 1) {
          // Update cache for the first page
          _cache[tab] = List.from(users);
          _lastFetchTime[tab] = now;
        }

        return users;
      }
      return [];
    } catch (e) {
      debugPrint('Professional ProfileRepository Error: $e');
      return [];
    }
  }

  static void clearCache() {
    _cache.clear();
    _lastFetchTime.clear();
  }
}

