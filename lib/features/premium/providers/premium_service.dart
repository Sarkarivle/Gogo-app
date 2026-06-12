import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/network/socket_service.dart';
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

  // New: Track message count for trial
  int _messagesSentCount = 0;
  int get messagesSentCount {
    final user = UserRepository().currentUser;
    if (user != null && user['messagesSentCount'] != null) {
      return user['messagesSentCount'];
    }
    return _messagesSentCount;
  }

  Future<void> incrementMessageCount() async {
    if (AppConfigService().isOneMessageTrialEnabled) {
      _messagesSentCount = messagesSentCount + 1;
      
      // OPTIMIZATION: Update UI state immediately
      hasAccess; 

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('messages_sent_count', _messagesSentCount);
      
      // SYNC TO BACKEND in background
      ApiService.post('/api/user/update-message-count', {'count': _messagesSentCount}).then((res) {
        if (res.statusCode == 200) {
           final data = jsonDecode(res.body);
           if (data['success'] == true && data['user'] != null) {
             UserRepository().updateLocalUser(data['user']);
           }
        }
      }).catchError((e) {
        debugPrint("Error syncing message count: $e");
      });
      
      debugPrint("🚀 [PREMIUM] Message Sent: $_messagesSentCount/${AppConfigService().freeMessageLimit}");
    }
  }

  bool get _isTrialExceeded => AppConfigService().isOneMessageTrialEnabled && messagesSentCount >= AppConfigService().freeMessageLimit;

  bool get isPremium => UserRepository().currentUser?['isPremium'] ?? false;
  String? get subscriptionStatus => UserRepository().currentUser?['subscription']?['status'];

  /// NEW: Check if user is currently in 'Freemium' mode
  bool get isFreemiumUser {
    if (isPremium) return false; // Paid users are never just freemium
    return FreemiumProvider().isTrialActive;
  }

  /// Logical check for ANY type of access (Paid OR Free Trial)
  bool get hasAccess {
    // 1. Premium users ALWAYS have full access
    if (isPremium) {
      if (accessNotifier.value != true) accessNotifier.value = true;
      if (statusNotifier.value != "PREMIUM") statusNotifier.value = "PREMIUM";
      return true;
    }

    bool access = isFreemiumUser;

    // 2. Trial Logic for Free Users
    if (!access && AppConfigService().isOneMessageTrialEnabled && !_isTrialExceeded) {
      access = true;
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
      // Parallelize config fetch and subscription sync
      await Future.wait([
        AppConfigService().fetchReviewMode(forceRefresh: true),
        syncSubscription(),
      ]);

      // 2. Final state re-evaluation
      hasAccess; 
      
      debugPrint('🔔 Real-time Access Updated: ${accessNotifier.value}, Status: ${statusNotifier.value}');
    } catch (e) {
      debugPrint('Error in refreshAccessState: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> init({bool force = false}) async {
    final userData = UserRepository().currentUser;
    if (userData != null) {
      // Listen for real-time premium updates from socket
      _setupSocketListener();

      // SYNC: Fetch latest toggle status from server
      await AppConfigService().fetchReviewMode();
      
      // Sync local trial usage
      final prefs = await SharedPreferences.getInstance();
      _messagesSentCount = prefs.getInt('messages_sent_count') ?? 0;
    }
  }

  void _setupSocketListener() {
    SocketService().eventStream.listen((event) {
      if (event['event'] == 'premium_status_refresh') {
        debugPrint("⚡ [PREMIUM] Real-time Status Refresh Received");
        refreshAccessState();
      }
    });
  }

  Future<void> syncSubscription() async {
    try {
      // CACHE BYPASS: Add timestamp to ensure fresh data from server
      final response = await ApiService.get('/api/payment/sync-status?_t=${DateTime.now().millisecondsSinceEpoch}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final userData = UserRepository().currentUser;
          if (userData != null) {
            // OPTIMIZATION: If backend returns full user, use it directly to ensure absolute sync
            if (data['user'] != null) {
              await UserRepository().updateLocalUser(data['user']);
              
              // Also sync the local trial count variable
              if (data['user']['messagesSentCount'] != null) {
                _messagesSentCount = data['user']['messagesSentCount'];
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('messages_sent_count', _messagesSentCount);
              }
              
              debugPrint('📡 Full User Synced from Payment API');
            } else {
              Map<String, dynamic> updatedData = Map.from(userData);
              updatedData['isPremium'] = data['isPremium'] ?? false;
              if (data['expiry'] != null) updatedData['premiumExpiry'] = data['expiry'];
              if (data['premiumPlan'] != null) updatedData['premiumPlan'] = data['premiumPlan'];
              
              // Sync trial count if available in root data
              if (data['messagesSentCount'] != null) {
                updatedData['messagesSentCount'] = data['messagesSentCount'];
                _messagesSentCount = data['messagesSentCount'];
              }

              // REAL-TIME SYNC: Update full subscription and history
              if (data['subscription'] != null) {
                updatedData['subscription'] = data['subscription'];
              } else if (data['status'] != null) {
                updatedData['subscription'] = {
                  ...(updatedData['subscription'] ?? {}),
                  'status': data['status']
                };
              }

              if (data['paymentHistory'] != null) {
                updatedData['paymentHistory'] = data['paymentHistory'];
              }

              if (data['offer'] != null) {
                AppConfigService().setDynamicOffer(data['offer']);
              }

              await UserRepository().updateLocalUser(updatedData);
            }
            
            if (data['offer'] != null) {
              AppConfigService().setDynamicOffer(data['offer']);
            }
            
            // Re-evaluate local access logic labels
            hasAccess; 
            debugPrint('📡 Subscription Synced: Premium=${UserRepository().currentUser?['isPremium']}');
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
