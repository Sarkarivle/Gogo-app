import 'package:flutter/material.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/shared/screens/offer_screen.dart';

class PremiumRepository {
  static final PremiumRepository _instance = PremiumRepository._internal();
  factory PremiumRepository() => _instance;
  PremiumRepository._internal();

  /// Sabse important function: Kya user ye action kar sakta hai?
  /// Agar nahi, to ye function khud Offer Page khol dega.
  bool checkAccessAndShowOffer(BuildContext context, {required String feature}) {
    final service = PremiumService();
    
    // 1. Premium users can do everything
    if (service.isPremium) return true;

    bool hasPermission = false;

    switch (feature) {
      case 'chat':
        // Check if user has free messages left
        hasPermission = service.hasAccess; 
        break;
      case 'audio_msg':
      case 'call':
      case 'media':
      case 'live_video':
      case 'unlimited_chat':
        // These are strictly for paid premium
        hasPermission = false; 
        break;
      default:
        hasPermission = service.hasAccess;
    }

    if (!hasPermission) {
      _navigateToOffer(context);
      return false;
    }

    return true;
  }

  void _navigateToOffer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfferScreen()),
    );
  }
}
