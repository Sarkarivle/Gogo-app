import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gogo/core/location/location_service.dart';

import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/core/services/app_visibility_coordinator.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/features/auth/screens/login_screen.dart';
import 'package:gogo/features/home/screens/home_screen.dart';
import 'package:gogo/features/news/screens/news_home_screen.dart';
import 'package:gogo/features/auth/screens/location_permission_screen.dart';
import 'package:gogo/features/premium/screens/trial_onboarding_screen.dart';
import 'package:gogo/features/auth/screens/profile_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final startTime = DateTime.now();

    try {
      // Parallelize remote config and user initialization
      await Future.wait([
        AppConfigService().fetchReviewMode(forceRefresh: true),
        UserRepository().initialize(),
      ]);
      
      final user = UserRepository().currentUser;

      if (user != null) {
        // Silent background tasks for logged in users
        UserRepository().updateLocation(user['phone']);
        NotificationService.updateTokenToServer();
        PremiumService().syncSubscription(); // Background sync
      }

      Widget nextScreen = const LoginScreen();

      if (AppVisibilityCoordinator().isHidden) {
        nextScreen = const NewsHomeScreen();
      } else if (user != null) {
        if (user['hasCompletedOnboarding'] == true) {
          nextScreen = const HomeScreen();
        } else {
          bool hasLocation = await LocationService().checkAndRequestPermission();
          bool hasAccess = PremiumService().hasAccess;

          if (!hasLocation) {
            nextScreen = const LocationPermissionScreen();
          } else if (hasAccess) {
            nextScreen = const ProfileSetupScreen();
          } else {
            nextScreen = const TrialOnboardingScreen();
          }
        }
      }

      // Smooth navigation with minimum delay for branding
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < 1500) await Future.delayed(Duration(milliseconds: 1500 - elapsed));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, anim, sec) => nextScreen,
            transitionsBuilder: (context, anim, sec, child) => FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
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
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orangeAccent.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/app_logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.bolt, color: Colors.orangeAccent, size: 80),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text("GoGo", style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const Spacer(),
              const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white24)),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
