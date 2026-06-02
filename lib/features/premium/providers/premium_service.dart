import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/app_config_service.dart';

import 'package:gogo/features/freemium/providers/freemium_provider.dart';

class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  // Global Notifiers for Access State Changes
  final ValueNotifier<bool> accessNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>("FREE");

  // New: Track if 1-message trial has been used
  bool _isOneMessageTrialUsed = false;
  bool get isOneMessageTrialUsed => _isOneMessageTrialUsed;

  Future<void> useOneMessageTrial() async {
    if (AppConfigService().isOneMessageTrialEnabled && !_isOneMessageTrialUsed) {
      _isOneMessageTrialUsed = true;
      
      // OPTIMIZATION: Update UI state immediately for zero-lag experience
      hasAccess; 

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('one_message_trial_used', true);
      
      // SYNC TO BACKEND in background
      ApiService.post('/api/user/mark-trial-used', {}).catchError((e) {
        debugPrint("Error syncing trial usage: $e");
        // ignore: invalid_return_type_for_catch_error
        return null;
      });
      
      debugPrint("🚀 [PREMIUM] 1-Message Trial USED. Access Revoked.");
    }
  }

  bool get isPremium => UserRepository().currentUser?['isPremium'] ?? false;
  String? get subscriptionStatus => UserRepository().currentUser?['subscription']?['status'];

  /// NEW: Check if user is currently in 'Freemium' mode
  bool get isFreemiumUser {
    if (isPremium) return false; // Paid users are never just freemium
    return FreemiumProvider().isTrialActive;
  }

  /// Logical check for ANY type of access (Paid OR Free Trial)
  bool get hasAccess {
    bool access = isPremium || isFreemiumUser;

    // 1-Message Trial Override for Google Compliance Switch
    if (AppConfigService().isStandardMode) {
      if (AppConfigService().isOneMessageTrialEnabled) {
        // If 1-message trial is active, access depends on whether they've used their 1 message
        access = !_isOneMessageTrialUsed;
      } else {
        // Google Toggle is ON, and trial is disabled -> Unlimited Access (Standard Review Mode)
        access = true;
      }
    }

    // Update notifiers only if values changed to save rebuilds
    if (accessNotifier.value != access) {
      accessNotifier.value = access;
    }
    
    final String currentLabel = accountStatusLabel;
    if (statusNotifier.value != currentLabel) {
      statusNotifier.value = currentLabel;
    }

    return access;
  }

  String get accountStatusLabel {
    if (isPremium) return "PREMIUM";
    
    // Google Compliance Mode Status Labels
    if (AppConfigService().isStandardMode) {
      if (AppConfigService().isOneMessageTrialEnabled) {
        return _isOneMessageTrialUsed ? "FREE (LIMIT EXCEEDED)" : "TRIAL ACCESS (1 MSG)";
      }
      return "FREE ACCESS";
    }

    if (isFreemiumUser) return "FREEMIUM";
    return "FREE";
  }

  bool _isRefreshing = false;

  /// Silent sync that triggers UI updates instantly
  Future<void> refreshAccessState() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes
    _isRefreshing = true;

    try {
      // 1. Force fetch fresh config from backend (Bypassing cache for compliance)
      await AppConfigService().fetchReviewMode(forceRefresh: true);
      
      // 2. Refresh user profile to sync isPremium status & trial status
      final userData = UserRepository().currentUser;
      if (userData != null && userData['phone'] != null) {
        final freshProfile = await UserRepository().fetchProfile(userData['phone']);
        
        // SYNC TRIAL STATUS FROM BACKEND
        if (freshProfile != null && freshProfile['oneMessageTrialUsed'] == true) {
          if (!_isOneMessageTrialUsed) {
             _isOneMessageTrialUsed = true;
             final prefs = await SharedPreferences.getInstance();
             await prefs.setBool('one_message_trial_used', true);
          }
        }
      }

      // 3. Update local access state & labels via Notifiers
      final bool currentAccess = hasAccess; 
      
      debugPrint('🔔 Real-time Access Updated: $currentAccess, Status: ${statusNotifier.value}');
    } catch (e) {
      debugPrint('Error in refreshAccessState: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> init({bool force = false}) async {
    final userData = UserRepository().currentUser;
    if (userData != null) {
      // SYNC: Fetch latest toggle status from server
      await AppConfigService().fetchReviewMode();
      
      // Sync local trial usage
      final prefs = await SharedPreferences.getInstance();
      _isOneMessageTrialUsed = prefs.getBool('one_message_trial_used') ?? false;
    }
  }

  Future<void> syncSubscription() async {
    try {
      final response = await ApiService.get('/api/payment/sync-status');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final userData = UserRepository().currentUser;
          if (userData != null) {
            Map<String, dynamic> updatedData = Map.from(userData);
            updatedData['isPremium'] = data['isPremium'] ?? false;
            updatedData['isStandardMode'] = data['isStandardMode'] ?? false;
            if (data['expiry'] != null) updatedData['premiumExpiry'] = data['expiry'];
            if (data['status'] != null) {
              updatedData['subscription'] = {
                ...(updatedData['subscription'] ?? {}),
                'status': data['status']
              };
            }
            await UserRepository().updateLocalUser(updatedData);
            debugPrint('📡 Subscription Synced: Premium=${updatedData['isPremium']}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing subscription: $e');
    }
  }

  Future<void> updatePremiumStatus(bool status, {String? statusName}) async {
    final userData = UserRepository().currentUser;
    if (userData != null) {
      Map<String, dynamic> updatedData = Map.from(userData);
      updatedData['isPremium'] = status;
      if (statusName != null) {
        updatedData['subscription'] = {
          ...(updatedData['subscription'] ?? {}),
          'status': statusName
        };
      }
      await UserRepository().updateLocalUser(updatedData);
    }
  }
}
