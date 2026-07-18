import 'package:flutter/material.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/core/services/monetization_orchestrator.dart';

class PremiumRepository {
  static final PremiumRepository _instance = PremiumRepository._internal();
  factory PremiumRepository() => _instance;
  PremiumRepository._internal();

  /// Sabse important function: Kya user ye action kar sakta hai?
  /// Agar nahi, to ye function khud Choice Popup ya Offer Page khol dega.
  /// [isStrict] means free message trial is NOT allowed for this feature.
  bool checkAccessAndShowOffer(BuildContext context, {required String feature, bool isStrict = false}) {
    final service = PremiumService();
    
    // 1. Check access based on strictness
    bool allowed = isStrict ? service.hasFullAccess : service.hasAccess;

    if (allowed) return true;

    // 2. If no access, trigger the intelligent decision popup
    _handleAccessDenied(context);
    return false;
  }

  void _handleAccessDenied(BuildContext context) {
    // Centralized redirection: Ad-Mode users get Reward Popup, Payer-Mode get Offer Page
    MonetizationOrchestrator().showChoicePopup(context);
  }
}
