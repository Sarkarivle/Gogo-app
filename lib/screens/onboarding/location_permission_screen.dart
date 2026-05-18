import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'trial_onboarding_screen.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermissionInitially();
  }

  Future<void> _checkPermissionInitially() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _navigateToNext();
    }
  }

  Future<void> _navigateToNext() async {
    // Get location immediately to show area name in next screen
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      String city = 'Unknown';
      String area = 'Unknown';
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        area = place.subLocality ?? place.thoroughfare ?? place.name ?? 'Unknown';
        city = place.locality ?? place.subAdministrativeArea ?? 'Unknown';
      }

      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        Map<String, dynamic> user = jsonDecode(userDataStr);
        user['area'] = area;
        user['city'] = city;
        await prefs.setString('user_data', jsonEncode(user));
        
        // Also sync with server
        await http.post(
          Uri.parse('http://72.61.170.181:5000/api/user/update-location'), 
          headers: {'Content-Type': 'application/json'}, 
          body: jsonEncode({
            'phone': user['phone'], 
            'lat': pos.latitude, 
            'lng': pos.longitude,
            'city': city,
            'area': area
          })
        );
      }
    } catch (e) { print(e); }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TrialOnboardingScreen()),
      );
    }
  }

  Future<void> _requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _navigateToNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.map_rounded, size: 100, color: Colors.white.withOpacity(0.8)),
                  const Positioned(
                    top: 40,
                    child: Icon(Icons.location_on, size: 50, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              "Enable Location",
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              "You'll need to enable your location in\norder to use GoGo",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16, height: 1.5),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text(
                  "ALLOW LOCATION",
                  style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
