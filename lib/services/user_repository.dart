import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class UserRepository {
  static final UserRepository _instance = UserRepository._internal();
  factory UserRepository() => _instance;
  UserRepository._internal();

  int _lastLocationUpdateTime = 0;

  Future<void> updateLocation(String phone, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle updates: only once every 5 minutes unless forced
    if (!force && (now - _lastLocationUpdateTime < 300000)) return;
    _lastLocationUpdateTime = now;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        
        String city = 'Unknown';
        String area = 'Unknown';
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            area = place.subLocality ?? place.thoroughfare ?? place.name ?? 'Unknown';
            city = place.locality ?? place.subAdministrativeArea ?? 'Unknown';
          }
        } catch (e) {
          debugPrint('Geocoding error: $e');
        }

        await ApiService.post('/api/user/update-location', {
          'phone': phone, 
          'lat': pos.latitude, 
          'lng': pos.longitude,
          'city': city,
          'area': area
        });

        // Update local storage
        final prefs = await SharedPreferences.getInstance();
        final userDataStr = prefs.getString('user_data');
        if (userDataStr != null) {
          Map<String, dynamic> userData = jsonDecode(userDataStr);
          userData['city'] = city;
          userData['area'] = area;
          userData['lat'] = pos.latitude;
          userData['lng'] = pos.longitude;
          await prefs.setString('user_data', jsonEncode(userData));
        }
      }
    } catch (e) {
      debugPrint('Update location error: $e');
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      final Map<String, dynamic> userData = jsonDecode(userDataStr);
      // Secure profile images in local storage
      if (userData['profileImages'] != null) {
        userData['profileImages'] = (userData['profileImages'] as List)
          .map((img) => ApiService.getSecureUrl(img))
          .toList();
      }
      return userData;
    }
    return null;
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('unique_device_id');
    if (deviceId == null) {
      deviceId = 'DEV_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9000 * (1.0 - (1.0 / (DateTime.now().millisecond + 1))))).toInt()}';
      // Simple random-ish ID without extra dependencies
      deviceId = 'DEV_${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('unique_device_id', deviceId);
    }
    return deviceId;
  }

  Future<void> trackEvent(String eventType, {String? customId}) async {
    try {
      final String distinctId = customId ?? await _getDeviceId();
      await ApiService.post('/api/user/track-event', {
        'eventType': eventType,
        'distinctId': distinctId,
      });
    } catch (e) {
      debugPrint('Track Event error: $e');
    }
  }

  void updateLocalUser(Map<String, dynamic> userData) {
    // This can be used to notify a ChangeNotifier or Stream if using state management
    debugPrint('🔄 UserRepository: Internal state updated for ${userData['phone']}');
  }

  Future<bool> deactivateAccount(String phone, String reason) async {
    try {
      final response = await ApiService.post('/api/user/deactivate', {
        'phone': phone,
        'reason': reason,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Deactivate Account error: $e');
      return false;
    }
  }
}
