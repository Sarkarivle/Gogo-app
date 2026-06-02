import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/premium/screens/trial_onboarding_screen.dart';

class AccessGuard {
  static final AccessGuard _instance = AccessGuard._internal();
  factory AccessGuard() => _instance;
  AccessGuard._internal();

  /// The Master Gatekeeper: Decides if a user can access a feature or must pay
  /// Returns [true] if access is allowed, [false] if redirected to paywall
  Future<bool> runWithAccessCheck(BuildContext context, {required FutureOr<void> Function() onAllowed}) async {
    final bool isStandardMode = AppConfigService().isStandardMode;
    final bool isPremium = PremiumService().isPremium;

    // 1. If Compliance Mode is ON, everyone has full access
    if (isStandardMode) {
      await onAllowed();
      return true;
    }

    // 2. If Compliance Mode is OFF, check for real Premium status
    if (isPremium) {
      await onAllowed();
      return true;
    }

    // 3. Otherwise, they are a 'Free' user - send to Trial/Payment page
    if (context.mounted) {
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => const TrialOnboardingScreen())
      );
    }
    return false;
  }
}
