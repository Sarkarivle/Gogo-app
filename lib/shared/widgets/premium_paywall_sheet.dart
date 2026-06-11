import 'package:flutter/material.dart';
import 'package:gogo/shared/screens/offer_screen.dart';

class PremiumPaywall {
  static void show(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfferScreen()),
    );
  }

  /// Big App Logic: Check access and show paywall if failed
  static bool checkAndShow(BuildContext context, bool hasAccess) {
    if (hasAccess) return true;
    show(context);
    return false;
  }
}
