import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/app_config_service.dart';

import 'package:gogo/features/freemium/providers/freemium_provider.dart';

class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  // Global Notifier for Access State Changes
  final ValueNotifier<bool> accessNotifier = ValueNotifier<bool>(true);

  bool get isPremium => UserRepository().currentUser?['isPremium'] ?? false;
  String? get subscriptionStatus => UserRepository().currentUser?['subscription']?['status'];

  /// NEW: Check if user is currently in 'Freemium' mode
  bool get isFreemiumUser {
    if (isPremium) return false; // Paid users are never just freemium
    return FreemiumProvider().isTrialActive;
  }

  /// Logical check for ANY type of access (Paid OR Free Trial)
  bool get hasAccess {
    final access = isPremium || isFreemiumUser;
    // Update notifier whenever this is checked to trigger UI shifts
    if (accessNotifier.value != access) {
      accessNotifier.value = access;
    }
    return access;
  }

  String get accountStatusLabel {
    if (isPremium) return "PREMIUM";
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
      
      // 2. Refresh user profile to sync isPremium status
      final userData = UserRepository().currentUser;
      if (userData != null && userData['phone'] != null) {
        await UserRepository().fetchProfile(userData['phone']);
      }

      // 3. Update local access state
      final bool currentAccess = isPremium || isFreemiumUser;
      
      // 4. Update notifier only if state actually changed to save rebuilds
      if (accessNotifier.value != currentAccess) {
        accessNotifier.value = currentAccess;
      }
      
      debugPrint('🔔 Real-time Access Updated: $currentAccess');
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
