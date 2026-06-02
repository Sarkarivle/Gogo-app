import 'package:flutter/material.dart';
import 'package:gogo/features/premium/screens/trial_onboarding_screen.dart';

class PremiumPaywall {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TrialOnboardingScreen(), // Using your existing screen as a sheet
    );
  }

  /// Big App Logic: Check access and show paywall if failed
  static bool checkAndShow(BuildContext context, bool hasAccess) {
    if (hasAccess) return true;
    show(context);
    return false;
  }
}
