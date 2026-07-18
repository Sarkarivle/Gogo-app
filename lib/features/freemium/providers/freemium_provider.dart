import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

class FreemiumProvider {
  static final FreemiumProvider _instance = FreemiumProvider._internal();
  factory FreemiumProvider() => _instance;
  FreemiumProvider._internal();

  /// Core logic: Does the user have access via Freemium Trial?
  bool get isTrialActive {
    final user = UserRepository().currentUser;
    if (user == null) return false;

    // If already a paid premium user, this trial logic doesn't apply to them
    if (user['isPremium'] == true) return false;

    // Check if Global Freemium Toggle is ON
    if (AppConfigService().isFreemiumActive) {
      final String? createdAtStr = user['createdAt'];
      if (createdAtStr == null) return false;

      try {
        final createdAt = DateTime.parse(createdAtStr);
        final now = DateTime.now();
        final duration = AppConfigService().freemiumDurationDays;

        // User is within the trial period (e.g., 1-2 days from signup)
        return now.difference(createdAt).inDays < duration;
      } catch (e) {
        debugPrint("Freemium Date Parsing Error: $e");
      }
    }
    return false;
  }

  /// Label for UI: "Free Trial" or "Premium"
  String get accessType {
    if (UserRepository().currentUser?['isPremium'] == true) return "PREMIUM";
    if (isTrialActive) return "FREE TRIAL";
    return "NONE";
  }
}
