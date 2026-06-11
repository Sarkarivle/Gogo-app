import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';
import 'package:gogo/core/location/location_repository.dart';
import 'package:gogo/core/services/presence_manager.dart';

class UserRepository {
  static final UserRepository _instance = UserRepository._internal();
  factory UserRepository() => _instance;
  UserRepository._internal();

  final ValueNotifier<Map<String, dynamic>?> userNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  SharedPreferences? _prefs;

  // Profile Cache for performance
  static final Map<String, Map<String, dynamic>> _profileCache = {};
  static final Map<String, int> _profileCacheTime = {};
  static const int _cacheTTL = 2 * 60 * 1000; // 2 minutes cache

  Map<String, dynamic>? get currentUser => userNotifier.value;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final userDataStr = _prefs?.getString('user_data');
    if (userDataStr != null) {
      userNotifier.value = jsonDecode(userDataStr);
    }
  }

  Future<void> updateLocation(String phone, {bool force = false}) async {
    final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
    await LocationRepository().updateLocation(normalizedPhone, force: force);
  }

  bool _isInitializing = false;
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (userNotifier.value != null) return userNotifier.value;
    
    if (_isInitializing) {
      // Wait for existing initialization to finish
      await Future.delayed(const Duration(milliseconds: 100));
      return userNotifier.value;
    }

    _isInitializing = true;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final userDataStr = _prefs?.getString('user_data');
      if (userDataStr != null) {
        final Map<String, dynamic> userData = jsonDecode(userDataStr);
        if (userData['profileImages'] != null) {
          userData['profileImages'] = (userData['profileImages'] as List)
            .map((img) => ApiService.getSecureUrl(img))
            .toList();
        }
        userNotifier.value = userData;
        return userData;
      }
    } finally {
      _isInitializing = false;
    }
    return null;
  }

  /// REFRESH PROFILE: Fetch latest user data from server (used for real-time status updates)
  Future<Map<String, dynamic>?> fetchProfile(String phone, {bool forceRefresh = false}) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      
      // Check cache first if not forced
      if (!forceRefresh && _profileCache.containsKey(normalizedPhone)) {
        final lastTime = _profileCacheTime[normalizedPhone] ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - lastTime < _cacheTTL) {
          return _profileCache[normalizedPhone];
        }
      }

      // CACHE BYPASS: Add timestamp to ensure fresh data from server
      final cacheBuster = forceRefresh ? '?_t=${DateTime.now().millisecondsSinceEpoch}' : '';
      final response = await ApiService.get('/api/user/profile/$normalizedPhone$cacheBuster');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['user'] != null) {
          final Map<String, dynamic> userData = data['user'];
          
          // Update PresenceManager with the latest isOnline status from server
          if (userData['phone'] != null) {
            PresenceManager().updateStatus(userData['phone'], userData['isOnline'] ?? false);
          }

          // Update Cache
          _profileCache[normalizedPhone] = userData;
          _profileCacheTime[normalizedPhone] = DateTime.now().millisecondsSinceEpoch;

          // Only update local user if it's the current user's profile
          if (currentUser != null && currentUser!['phone'] == userData['phone']) {
            await updateLocalUser(userData);
          }
          return userData;
        }
      }
    } catch (e) {
      debugPrint('Fetch Profile error: $e');
    }
    return null;
  }

  Future<String> _getDeviceId() async {
    _prefs ??= await SharedPreferences.getInstance();
    String? deviceId = _prefs?.getString('unique_device_id');
    if (deviceId == null) {
      deviceId = 'DEV_${DateTime.now().microsecondsSinceEpoch}';
      await _prefs?.setString('unique_device_id', deviceId);
    }
    return deviceId;
  }

  Future<void> trackEvent(String eventType, {String? customId, String? eventId, Map<String, dynamic>? metadata}) async {
    try {
      final String distinctId = customId ?? await _getDeviceId();
      ApiService.post('/api/user/track-event', {
        'eventType': eventType,
        'distinctId': distinctId,
        'metadata': {
          ...?metadata,
          ...?eventId == null ? null : {'event_id': eventId},
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }
      });
    } catch (e) {
      debugPrint('Track Event error: $e');
    }
  }

  Future<void> updateLocalUser(Map<String, dynamic> userData) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (userData.isEmpty) {
      await _prefs?.remove('user_data');
      userNotifier.value = null;
      _profileCache.clear();
      _profileCacheTime.clear();
    } else {
      // Normalize phone before saving locally for consistency
      if (userData['phone'] != null) {
        userData['phone'] = PhoneUtils.normalize(userData['phone']);
      }
      
      // Ensure we create a NEW instance to trigger ValueListenableBuilder correctly
      final freshData = Map<String, dynamic>.from(userData);
      
      await _prefs?.setString('user_data', jsonEncode(freshData));
      userNotifier.value = freshData;

      // UPDATE CACHE: Prevent stale data overwriting fresh syncs
      if (freshData['phone'] != null) {
        final normalized = PhoneUtils.normalize(freshData['phone']) ?? freshData['phone'];
        _profileCache[normalized] = freshData;
        _profileCacheTime[normalized] = DateTime.now().millisecondsSinceEpoch;
      }
    }
  }

  Future<bool> deactivateAccount(String phone, String reason) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      final response = await ApiService.post('/api/user/deactivate', {
        'phone': normalizedPhone,
        'reason': reason,
      });

      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
