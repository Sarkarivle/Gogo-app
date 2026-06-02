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
  Position? _lastSentPosition;
  final int _timeThrottle = 300000; // 5 minutes
  final double _distanceThrottle = 500.0; // 500 meters

  /// Updates the user's location on the server and locally with Pro-Level Throttling
  Future<void> updateLocation(String phone, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 1. Get Current Position (includes Privacy Fuzzy Noise)
    final Position? currentPosition = await LocationService().getCurrentPosition();
    if (currentPosition == null) return;

    // 2. Pro-App Throttling: Check Time AND Distance
    if (!force) {
      bool isTimePassed = (now - _lastUpdateTime >= _timeThrottle);
      
      double distanceMoved = 0;
      if (_lastSentPosition != null) {
        distanceMoved = Geolocator.distanceBetween(
          _lastSentPosition!.latitude, _lastSentPosition!.longitude,
          currentPosition.latitude, currentPosition.longitude
        );
      }

      // If neither time nor distance threshold is met, skip update
      if (!isTimePassed && distanceMoved < _distanceThrottle && _lastSentPosition != null) {
        return;
      }
    }

    _lastUpdateTime = now;
    _lastSentPosition = currentPosition;

    try {
      // Get readable address
      final address = await LocationService().getAddressFromCoordinates(
        currentPosition.latitude, 
        currentPosition.longitude
      );

      final String? city = address['city'];
      final String? area = address['area'];

      final Map<String, dynamic> locationData = {
        'phone': phone,
        'lat': currentPosition.latitude,
        'lng': currentPosition.longitude,
      };

      if (city != null) locationData['city'] = city;
      if (area != null) locationData['area'] = area;

      // Update Server
      ApiService.post('/api/user/update-location', locationData);

      // Update Local State
      final currentUser = UserRepository().currentUser;
      if (currentUser != null) {
        Map<String, dynamic> updatedUser = Map.from(currentUser);
        if (city != null) updatedUser['city'] = city;
        if (area != null) updatedUser['area'] = area;
        updatedUser['lat'] = currentPosition.latitude;
        updatedUser['lng'] = currentPosition.longitude;
        
        await UserRepository().updateLocalUser(updatedUser);
      }
      
      debugPrint('🚀 [PRO_LOCATION] Updated: $city, $area. Force: $force');
    } catch (e) {
      debugPrint('Location update process failed: $e');
    }
  }
}
