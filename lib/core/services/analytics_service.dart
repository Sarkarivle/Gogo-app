import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/services/app_config_service.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();

  static bool _canTrack(String target) {
    final config = AppConfigService().trackingConfig;
    if (config == null) return true; // Default to true if not loaded yet
    
    if (config['isTrackingEnabled'] == false) return false;

    if (target == 'firebase') {
      return config['isFirebaseEnabled'] != false;
    }
    
    if (target == 'meta') {
      return config['isMetaEnabled'] == true;
    }

    return true;
  }

  static bool _shouldTrackEvent(String eventType) {
    final config = AppConfigService().trackingConfig;
    if (config == null) return true;

    switch (eventType) {
      case 'sign_up':
        return config['trackSignUp'] != false;
      case 'purchase':
        return config['trackPurchase'] != false;
      case 'trial':
        return config['trackTrial'] != false;
      default:
        return true;
    }
  }

  // 1. App Open Event
  static Future<void> logAppOpen() async {
    if (_canTrack('firebase')) {
      await _analytics.logAppOpen();
    }
    // Meta tracks app opens automatically if initialized
    debugPrint('📊 [Analytics] App Open logged');
  }

  // 2. User Sign-up/Registration
  static Future<void> logSignUp(String method) async {
    if (!_shouldTrackEvent('sign_up')) return;

    if (_canTrack('firebase')) {
      await _analytics.logSignUp(signUpMethod: method);
    }

    if (_canTrack('meta')) {
      await _facebookAppEvents.logCompletedRegistration(registrationMethod: method);
    }
    
    debugPrint('📊 [Analytics] Sign Up logged ($method)');
  }

  // 3. Random Call Started
  static Future<void> logStartCall(String type) async {
    final params = {
      'call_type': type,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_canTrack('firebase')) {
      await _analytics.logEvent(name: 'start_call', parameters: params);
    }

    if (_canTrack('meta')) {
      await _facebookAppEvents.logEvent(name: 'start_call', parameters: params);
    }

    debugPrint('📊 [Analytics] Start Call logged: $type');
  }

  // 4. Premium Subscription/Purchase
  static Future<void> logPurchase(double amount, String currency, String planId) async {
    if (!_shouldTrackEvent('purchase')) return;

    if (_canTrack('firebase')) {
      await _analytics.logEvent(
        name: 'purchase_premium',
        parameters: {'value': amount, 'currency': currency, 'item_id': planId},
      );
      await _analytics.logPurchase(
        value: amount,
        currency: currency,
        items: [AnalyticsEventItem(itemId: planId, itemName: 'Premium Plan')],
      );
    }

    if (_canTrack('meta')) {
      await _facebookAppEvents.logPurchase(amount: amount, currency: currency, parameters: {'item_id': planId});
    }

    debugPrint('📊 [Analytics] Purchase logged: $amount $currency');
  }

  // 5. User Profile View
  static Future<void> logViewProfile(String userId) async {
    final params = {'target_user_id': userId};
    
    if (_canTrack('firebase')) {
      await _analytics.logEvent(name: 'view_profile', parameters: params);
    }
    
    if (_canTrack('meta')) {
      await _facebookAppEvents.logEvent(name: 'view_profile', parameters: params);
    }
  }

  // 6. Custom Screen Tracking
  static Future<void> logScreenView(String screenName) async {
    if (_canTrack('firebase')) {
      await _analytics.logScreenView(screenName: screenName);
    }
    // Meta also supports screen views but requires custom events or automatic tracking
    debugPrint('📊 [Analytics] Screen View: $screenName');
  }

  // 7. Generic Event Wrapper
  static Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    // Specific check for trial events
    if (name.contains('trial') && !_shouldTrackEvent('trial')) return;

    if (_canTrack('firebase')) {
      await _analytics.logEvent(name: name, parameters: parameters);
    }

    if (_canTrack('meta')) {
      await _facebookAppEvents.logEvent(name: name, parameters: parameters);
    }

    debugPrint('📊 [Analytics] Event: $name ${parameters ?? ""}');
  }
}
