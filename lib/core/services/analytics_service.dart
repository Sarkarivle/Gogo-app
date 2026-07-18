import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

/// Clean & Robust Implementation of Facebook App Events SDK
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();
  static bool _isMetaActivated = false;

  static bool _canTrack(String target) {
    final config = AppConfigService().trackingConfig;
    if (config == null) return true;
    if (config['isTrackingEnabled'] == false) return false;
    if (target == 'firebase') return config['isFirebaseEnabled'] != false;
    if (target == 'meta') return config['isMetaEnabled'] == true;
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

  /// 1. Initialize & Activate SDK
  static Future<void> logAppOpen() async {
    if (_canTrack('firebase')) await _analytics.logAppOpen();

    if (_canTrack('meta')) {
      await _facebookAppEvents.setAdvertiserTracking(enabled: true);
      await _facebookAppEvents.activateApp();
      _isMetaActivated = true;
      debugPrint('📊 [Analytics] Facebook SDK Activated');
    }
  }

  /// 2. Track Standard Events
  static Future<void> logSignUp(String method) async {
    if (!_shouldTrackEvent('sign_up')) return;
    if (_canTrack('firebase')) await _analytics.logSignUp(signUpMethod: method);
    if (_canTrack('meta')) await _facebookAppEvents.logCompletedRegistration(registrationMethod: method);
    _syncWithBackend('onboarding_completed');
  }

  static Future<void> logPurchase(double amount, String currency, String planId, {String? eventId}) async {
    if (!_shouldTrackEvent('purchase')) return;
    if (_canTrack('firebase')) {
      await _analytics.logPurchase(value: amount, currency: currency, items: [AnalyticsEventItem(itemId: planId, itemName: 'Premium Plan')]);
    }
    final String resolvedEventId = eventId ?? "pur_${DateTime.now().millisecondsSinceEpoch}_$planId";
    if (_canTrack('meta')) {
      await _facebookAppEvents.logPurchase(amount: amount, currency: currency, parameters: {
        'content_id': planId,
        'event_id': resolvedEventId,
      });
    }
    _syncWithBackend('premium_activated', eventId: resolvedEventId, metadata: {'amount': amount, 'currency': currency, 'planId': planId});
  }

  /// 3. Track Video/Audio Calls
  static Future<void> logStartCall(String type) async {
    final params = {'call_type': type};
    if (_canTrack('firebase')) await _analytics.logEvent(name: 'start_call', parameters: params);
    if (_canTrack('meta')) await _facebookAppEvents.logEvent(name: 'start_call', parameters: params);
    _syncWithBackend('start_call', metadata: params);
  }

  /// 4. Custom Screen Tracking
  static Future<void> logScreenView(String screenName) async {
    if (_canTrack('firebase')) await _analytics.logScreenView(screenName: screenName);
    debugPrint('📊 [Analytics] Screen View: $screenName');
  }

  /// 5. Custom Profile View
  static Future<void> logViewProfile(String userId) async {
    final params = {'target_user_id': userId};
    if (_canTrack('firebase')) await _analytics.logEvent(name: 'view_profile', parameters: params);
    if (_canTrack('meta')) await _facebookAppEvents.logEvent(name: 'view_profile', parameters: params);
    _syncWithBackend('view_profile', metadata: params);
  }

  /// 6. Generic/Custom Events
  static Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    if (name.contains('trial') && !_shouldTrackEvent('trial')) return;
    
    final String eventId = "${DateTime.now().millisecondsSinceEpoch}_$name";
    final Map<String, Object> finalParams = {...?parameters, 'event_id': eventId};

    if (_canTrack('firebase')) await _analytics.logEvent(name: name, parameters: finalParams);
    if (_canTrack('meta')) await _facebookAppEvents.logEvent(name: name, parameters: finalParams);
    
    _syncWithBackend(name, eventId: eventId, metadata: parameters);
    debugPrint('📊 [Analytics] Event: $name');
  }

  /// Sync Helper for Backend & CAPI
  static void _syncWithBackend(String eventName, {String? eventId, Map<String, dynamic>? metadata}) {
    final user = UserRepository().currentUser;
    final String? phone = user?['phone']?.toString();
    UserRepository().trackEvent(eventName, customId: phone, eventId: eventId, metadata: metadata);
  }

  static Future<void> activateMetaIfEnabled() async {
    if (!_isMetaActivated) await logAppOpen();
  }
}
