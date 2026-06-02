import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class AuthRepository {
  static final AuthRepository _instance = AuthRepository._internal();
  factory AuthRepository() => _instance;
  AuthRepository._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  User? get currentFirebaseUser => _auth.currentUser;

  Future<void> logout() async {
    try {
      await _auth.signOut();
      await UserRepository().updateLocalUser({}); // Clear user data
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  Future<Map<String, dynamic>> handleBackendLogin(String phone) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      
      // Re-fetch App Config on login
      await AppConfigService().fetchReviewMode();
      
      final String? firebaseToken = await _auth.currentUser?.getIdToken();

      final response = await ApiService.post('/api/user/login', {
        'phone': normalizedPhone,
        'firebaseToken': firebaseToken,
      });
      
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        return {
          'success': true,
          'user': data['user'],
          'token': data['token'],
        };
      } else {
        // Try Registration if login fails (New User)
        final regResponse = await ApiService.post('/api/user/register', {
          'phone': normalizedPhone,
          'name': 'User ${normalizedPhone.substring(normalizedPhone.length - 4)}',
          'age': 18,
          'isPremium': false,
          'hasCompletedOnboarding': false,
          'firebaseToken': firebaseToken,
        });
        
        final regData = jsonDecode(regResponse.body);
        if (regData['success'] == true) {
          return {
            'success': true,
            'user': regData['user'],
            'token': regData['token'],
          };
        } else {
          return {'success': false, 'message': regData['message'] ?? 'Registration failed'};
        }
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<void> saveSession(dynamic userData, String? token) async {
    await UserRepository().updateLocalUser(userData);
    
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    }
    
    await NotificationService.updateTokenToServer();
  }
}
