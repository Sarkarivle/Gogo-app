import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/shared/screens/offer_screen.dart';

class AccessGuard {
  static final AccessGuard _instance = AccessGuard._internal();
  factory AccessGuard() => _instance;
  AccessGuard._internal();

  /// The Master Gatekeeper: Decides if a user can access a feature or must pay
  /// Returns [true] if access is allowed, [false] if redirected to paywall
  Future<bool> runWithAccessCheck(BuildContext context, {required FutureOr<void> Function() onAllowed}) async {
    final bool hasAccess = PremiumService().hasAccess;

    // 1. Check for ANY type of access (Paid, Freemium Trial, or Standard Compliance Access)
    if (hasAccess) {
      await onAllowed();
      return true;
    }

    // 2. Otherwise, they are restricted (e.g., 1-Msg Trial Exceeded) - send to Offer Page
    if (context.mounted) {
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => const OfferScreen())
      );
    }
    return false;
  }
}
