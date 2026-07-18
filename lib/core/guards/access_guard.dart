import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/core/services/monetization_orchestrator.dart';

class AccessGuard {
  static final AccessGuard _instance = AccessGuard._internal();
  factory AccessGuard() => _instance;
  AccessGuard._internal();

  /// The Master Gatekeeper: Decides if a user can access a feature or must pay
  /// Returns [true] if access is allowed, [false] if redirected to paywall
  Future<bool> runWithAccessCheck(BuildContext context, {
    required FutureOr<void> Function() onAllowed,
    bool isStrict = true, // Default to true for intercepted UI elements
  }) async {
    final bool hasAccess = isStrict ? PremiumService().hasFullAccess : PremiumService().hasAccess;

    // 1. Check for ANY type of access (Paid, Freemium Trial, Temporary Gold, or Standard Compliance Access)
    if (hasAccess) {
      await onAllowed();
      return true;
    }

    // 2. Otherwise, they are restricted - send to the intelligent choice interceptor
    if (context.mounted) {
      MonetizationOrchestrator().showChoicePopup(context);
    }
    return false;
  }
}
