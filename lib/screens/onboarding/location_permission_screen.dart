import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import 'trial_onboarding_screen.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionInitially();
  }

  Future<void> _checkPermissionInitially() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _fetchAndNavigate();
    }
  }

  Future<void> _fetchAndNavigate() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      // Step 1: Get coordinates quickly (Medium accuracy is enough and fast)
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      
      // Step 2: Get Address (Fast usually)
      String city = 'Unknown';
      String area = 'Unknown';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 3));
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          area = place.subLocality ?? place.thoroughfare ?? place.name ?? 'Unknown';
          city = place.locality ?? place.subAdministrativeArea ?? 'Unknown';
        }
      } catch (e) {
        debugPrint("Geocoding timeout or error: $e");
      }

      // Step 3: Save Locally (Mandatory)
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        Map<String, dynamic> user = jsonDecode(userDataStr);
        user['area'] = area;
        user['city'] = city;
        user['lat'] = pos.latitude;
        user['lng'] = pos.longitude;
        await prefs.setString('user_data', jsonEncode(user));
        
        // Step 4: Sync with server (Fire and forget or short timeout to keep it fast)
        ApiService.post('/api/user/update-location', {
          'phone': user['phone'], 
          'lat': pos.latitude, 
          'lng': pos.longitude,
          'city': city,
          'area': area
        }).timeout(const Duration(seconds: 2)).catchError((e) => http.Response('Error', 500));
      }

      // Step 5: Navigate
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const TrialOnboardingScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      debugPrint("Location fetch error: $e");
      // Even if location fails, we should ideally let them proceed if we want it to be "fast" 
      // but user said "location save karna jaroori hai". 
      // So if it fails hard, we stop processing.
      if (mounted) setState(() => _isProcessing = false);
      _showErrorSnackBar("Could not get location. Please try again.");
    }
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)
    );
  }

  Future<void> _requestPermission() async {
    if (_isProcessing) return;
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _fetchAndNavigate();
    } else if (permission == LocationPermission.deniedForever) {
      _showErrorSnackBar("Location permission is permanently denied. Please enable it in settings.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF2A0D17).withValues(alpha: 0.8),
              const Color(0xFF0F0F0F),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              children: [
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 1),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withValues(alpha: 0.05),
                          blurRadius: 40,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.location_on_rounded, size: 80, color: Colors.orangeAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
                const Text(
                  "Enable Location",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "To find amazing people near you, we need to know your location.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 16,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _requestPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      elevation: 8,
                      shadowColor: Colors.orangeAccent.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      disabledBackgroundColor: Colors.orangeAccent.withValues(alpha: 0.5),
                    ),
                    child: _isProcessing 
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                        )
                      : const Text(
                          "Allow Access",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
