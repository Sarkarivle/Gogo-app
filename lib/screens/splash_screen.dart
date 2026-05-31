import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/app_config_service.dart';
import '../services/app_visibility_coordinator.dart';
import '../services/premium_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'news_home_screen.dart';
import 'onboarding/location_permission_screen.dart';
import 'onboarding/trial_onboarding_screen.dart';
import 'onboarding/profile_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.outBack)),
    );

    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Minimum show time for Splash (to show branding)
    DateTime startTime = DateTime.now();

    try {
      // 2. Load basic services
      await AppConfigService().fetchReviewMode();
      
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      final authToken = prefs.getString('auth_token');

      // 3. Decide Navigation
      Widget nextScreen = const LoginScreen();

      if (AppVisibilityCoordinator().isHidden) {
        nextScreen = const NewsHomeScreen();
      } else if (userDataStr != null && authToken != null) {
        // Logged in user - Sync latest status from server (The "Big App" Sync)
        await AppConfigService().syncSubscription();
        await PremiumService().init();

        final userData = jsonDecode(userDataStr);
        
        if (userData['hasCompletedOnboarding'] == true) {
          nextScreen = const HomeScreen();
        } else {
          // Check Location & Subscription
          LocationPermission permission = await Geolocator.checkPermission();
          bool hasLocation = (permission == LocationPermission.always || permission == LocationPermission.whileInUse);
          bool bypassTrial = AppConfigService().isPremium || AppConfigService().isStandardMode;

          if (!hasLocation) {
            nextScreen = const LocationPermissionScreen();
          } else if (bypassTrial) {
            nextScreen = const ProfileSetupScreen();
          } else {
            nextScreen = const TrialOnboardingScreen();
          }
        }
      }

      // 4. Ensure Splash stays for at least 2 seconds for smooth UX
      DateTime endTime = DateTime.now();
      int elapsed = endTime.difference(startTime).inMilliseconds;
      if (elapsed < 2000) {
        await Future.delayed(Duration(milliseconds: 2000 - elapsed));
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      debugPrint("Initialization Error: $e");
      // Fallback to login on error
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A0D17),
              Color(0xFF0F0F0F),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/app_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.bolt,
                            color: Colors.orangeAccent,
                            size: 80,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "GoGo",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      "Premium Dating Experience",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 50),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
