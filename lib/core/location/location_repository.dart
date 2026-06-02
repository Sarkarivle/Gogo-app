import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/location/location_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:geolocator/geolocator.dart';

class LocationRepository {
  static final LocationRepository _instance = LocationRepository._internal();
  factory LocationRepository() => _instance;
  LocationRepository._internal();

  int _lastUpdateTime = 0;
  final int _throttleDuration = 300000; // 5 minutes

  /// Updates the user's location on the server and locally
  Future<void> updateLocation(String phone, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastUpdateTime < _throttleDuration)) {
      return;
    }
    _lastUpdateTime = now;

    try {
      final Position? position = await LocationService().getCurrentPosition();
      if (position == null) return;

      // Get readable address
      final address = await LocationService().getAddressFromCoordinates(
        position.latitude, 
        position.longitude
      );

      final String? city = address['city'];
      final String? area = address['area'];

      // Prepare data for server
      final Map<String, dynamic> locationData = {
        'phone': phone,
        'lat': position.latitude,
        'lng': position.longitude,
      };

      if (city != null && city.toLowerCase() != 'unknown') locationData['city'] = city;
      if (area != null && area.toLowerCase() != 'unknown') locationData['area'] = area;

      // 1. Update Server (Fire and forget or async)
      ApiService.post('/api/user/update-location', locationData).then((response) {
        if (response.statusCode != 200) {
          debugPrint('Failed to update location on server: ${response.statusCode}');
        }
      }).catchError((e) {
        debugPrint('Location server sync error: $e');
      });

      // 2. Update Local State via UserRepository
      final currentUser = UserRepository().currentUser;
      if (currentUser != null) {
        Map<String, dynamic> updatedUser = Map.from(currentUser);
        if (city != null) updatedUser['city'] = city;
        if (area != null) updatedUser['area'] = area;
        updatedUser['lat'] = position.latitude;
        updatedUser['lng'] = position.longitude;
        
        await UserRepository().updateLocalUser(updatedUser);
      }
      
      debugPrint('✅ Location updated: $city, $area (${position.latitude}, ${position.longitude})');
    } catch (e) {
      debugPrint('Location update process failed: $e');
    }
  }
}
