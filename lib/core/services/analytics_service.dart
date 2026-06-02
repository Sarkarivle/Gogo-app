import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 1. App Open Event
  static Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
    debugPrint('📊 [Analytics] App Open logged');
  }

  // 2. User Sign-up/Registration
  static Future<void> logSignUp(String method) async {
    await _analytics.logSignUp(signUpMethod: method);
    debugPrint('📊 [Analytics] Sign Up logged ($method)');
  }

  // 3. Random Call Started (GTM/FB Ads ke liye sabse zaruri)
  static Future<void> logStartCall(String type) async {
    await _analytics.logEvent(
      name: 'start_call',
      parameters: {
        'call_type': type, // video or audio
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    debugPrint('📊 [Analytics] Start Call logged: $type');
  }

  // 4. Premium Subscription/Purchase
  static Future<void> logPurchase(double amount, String currency, String planId) async {
    await _analytics.logEvent(
      name: 'purchase_premium',
      parameters: {
        'value': amount,
        'currency': currency,
        'item_id': planId,
      },
    );
    // Standard purchase event for Google/FB Ads optimization
    await _analytics.logPurchase(
      value: amount,
      currency: currency,
      items: [AnalyticsEventItem(itemId: planId, itemName: 'Premium Plan')],
    );
    debugPrint('📊 [Analytics] Purchase logged: $amount $currency');
  }

  // 5. User Profile View
  static Future<void> logViewProfile(String userId) async {
    await _analytics.logEvent(
      name: 'view_profile',
      parameters: {'target_user_id': userId},
    );
  }

  // 6. Custom Screen Tracking
  static Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
    debugPrint('📊 [Analytics] Screen View: $screenName');
  }
}
