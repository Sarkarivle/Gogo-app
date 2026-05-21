import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/onboarding/trial_onboarding_screen.dart';

class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      final data = jsonDecode(userData);
      _isPremium = data['isPremium'] ?? false;
    }
  }

  /// Checks if user is premium. If not, redirects to trial onboarding screen.
  /// Returns true if premium, false otherwise.
  Future<bool> checkPremiumAndRedirect(BuildContext context) async {
    await init(); // Ensure we have latest local state
    if (_isPremium) return true;

    // Redirect to Trial Onboarding Screen (₹1 Highlight Page)
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TrialOnboardingScreen()),
      );
    }
    return false;
  }

  Future<void> updatePremiumStatus(bool status) async {
    _isPremium = status;
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      Map<String, dynamic> data = jsonDecode(userDataStr);
      data['isPremium'] = status;
      await prefs.setString('user_data', jsonEncode(data));
    }
  }
}
