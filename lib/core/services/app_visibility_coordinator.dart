import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import 'package:gogo/features/news/screens/news_home_screen.dart';
import 'package:gogo/features/home/screens/home_screen.dart';
import 'package:gogo/features/auth/screens/login_screen.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

class AppVisibilityCoordinator {
  static final AppVisibilityCoordinator _instance = AppVisibilityCoordinator._internal();
  factory AppVisibilityCoordinator() => _instance;
  AppVisibilityCoordinator._internal();

  static const String _keyIsHidden = 'is_app_hidden';

  bool _isHidden = false;
  bool get isHidden => _isHidden;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isHidden = prefs.getBool(_keyIsHidden) ?? false;
  }

  Future<void> setHidden(bool hidden) async {
    _isHidden = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsHidden, hidden);
  }

  void toggleHideMode(BuildContext context) async {
    if (!_isHidden) {
      // Show confirmation popup in Hindi
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'क्या आप ऐप को Hide Mode में बदलना चाहते हैं?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: const Text(
            'Hide Mode चालू करने के बाद, यह ऐप एक न्यूज़ ऐप की तरह दिखाई देगा।',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Yes, Hide App', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await setHidden(true);
        if (!context.mounted) return;
        // Restart app navigation to NewsHomeScreen
        _restartApp(context);
      }
    } else {
      await setHidden(false);
      if (!context.mounted) return;
      _restartApp(context);
    }
  }

  void _restartApp(BuildContext context) async {
    if (!context.mounted) return;

    final user = UserRepository().currentUser;
    Widget initialScreen = const LoginScreen();
    
    if (_isHidden) {
      initialScreen = const NewsHomeScreen();
    } else if (user != null) {
      initialScreen = const HomeScreen();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => initialScreen),
      (route) => false,
    );
  }
}
