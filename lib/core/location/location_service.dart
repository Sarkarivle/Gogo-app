import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Checks and requests location permissions
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Gets the current position with "Fuzzy Noise" for privacy (Standard in Pro Apps)
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100, // Minimal hardware trigger
        ),
      );

      // Add "Strong Privacy Noise" (Offsetting by ~500-800 meters)
      // High-level privacy to ensure exact building cannot be identified
      final random = Random();
      // 0.009 degrees is approximately 1km. 
      // (random - 0.5) * 0.009 gives a range of +/- 500 meters roughly.
      double latOffset = (random.nextDouble() - 0.5) * 0.009; 
      double lngOffset = (random.nextDouble() - 0.5) * 0.009;

      return Position(
        latitude: pos.latitude + latOffset,
        longitude: pos.longitude + lngOffset,
        timestamp: pos.timestamp,
        accuracy: pos.accuracy,
        altitude: pos.altitude,
        heading: pos.heading,
        speed: pos.speed,
        speedAccuracy: pos.speedAccuracy,
        altitudeAccuracy: pos.altitudeAccuracy,
        headingAccuracy: pos.headingAccuracy,
      );
    } catch (e) {
      debugPrint('Error getting position: $e');
      return null;
    }
  }

  /// Optimized Address Extraction
  Future<Map<String, String?>> getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        
        String? area = place.subLocality ?? place.thoroughfare ?? place.name;
        String? city = place.locality ?? place.subAdministrativeArea;

        if (area != null && (area.toLowerCase() == 'null' || area.toLowerCase() == 'unknown')) area = null;
        if (city != null && (city.toLowerCase() == 'null' || city.toLowerCase() == 'unknown')) city = null;
        
        return {
          'city': city,
          'area': area,
          'state': place.administrativeArea,
          'country': place.country,
        };
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return {'city': null, 'area': null};
  }
}
