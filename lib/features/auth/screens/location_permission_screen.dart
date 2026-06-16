import 'package:flutter/material.dart';
import 'package:gogo/core/location/location_service.dart';
import 'package:gogo/core/location/location_repository.dart';
import 'package:geolocator/geolocator.dart';

import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/auth/screens/profile_setup_screen.dart';
import 'package:gogo/features/home/screens/home_screen.dart';

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
    // Removed automatic check to allow user to trigger it via button
  }

  void _showToast(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: isSuccess ? Colors.green.withValues(alpha: 0.8) : Colors.orangeAccent.withValues(alpha: 0.8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _fetchAndNavigate() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      // 1. Parallel Sync: We wait for Location and Subscription in parallel
      final results = await Future.wait([
        LocationService().getCurrentPosition(),
        PremiumService().syncSubscription(),
        AppConfigService().fetchReviewMode(),
      ]);

      final Position? pos = results[0] as Position?;
      final user = UserRepository().currentUser;

      if (pos != null && user != null) {
        // Use the new repository for centralized logic
        // CRITICAL: We await this so the server has the location BEFORE the user lands on Home
        await LocationRepository().updateLocation(user['phone'], force: true, providedPosition: pos);
      } else if (user == null) {
        throw "User session expired";
      }

      // 2. Core Logic decision happens ONLY AFTER syncSubscription completes
      if (mounted) {
        final user = UserRepository().currentUser;
        bool hasCompleted = user?['hasCompletedOnboarding'] ?? false;

        Widget nextScreen = hasCompleted ? const HomeScreen() : const ProfileSetupScreen();

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      debugPrint("Navigation Sync Error: $e");
      if (mounted) {
        final user = UserRepository().currentUser;
        if (user != null) {
          // Even on sync failure, use whatever we have to decide next screen
          bool hasCompleted = user['hasCompletedOnboarding'] ?? false;
          Widget nextScreen = hasCompleted ? const HomeScreen() : const ProfileSetupScreen();
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => nextScreen));
        } else {
          setState(() => _isProcessing = false);
          _showToast("Sync failed. Check your internet connection.");
        }
      }
    }
  }

  Future<void> _requestPermission() async {
    if (_isProcessing) return;
    bool hasPermission = await LocationService().checkAndRequestPermission();
    
    if (hasPermission) {
      _fetchAndNavigate();
    } else {
      _showToast("Location permission is required to find people near you.");
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
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [const Color(0xFF2A0D17).withValues(alpha: 0.8), const Color(0xFF0F0F0F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Center(child: Icon(Icons.location_on_rounded, size: 80, color: Colors.orangeAccent)),
                ),
                const SizedBox(height: 50),
                const Text("Enable Location", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                Text(
                  "To find amazing people near you, we need to know your location.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity, height: 65,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _requestPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isProcessing 
                      ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 3)
                      : const Text("Allow Access", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
