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
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        
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
      return jsonDecode(userDataStr);
    }
    return null;
  }
}
