import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class AuthRepository {
  static final AuthRepository _instance = AuthRepository._internal();
  factory AuthRepository() => _instance;
  AuthRepository._internal();

  Future<Map<String, dynamic>> sendOTP(String phone) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      final response = await ApiService.post('/api/user/send-otp', {'phone': normalizedPhone});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': data['success'] == true, 'message': data['message'], 'reqId': data['reqId']};
      }
      try {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Server error'};
      } catch (_) {
        return {'success': false, 'message': 'Server error'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> handleBackendLogin(String phone, {required String otp, required String? reqId}) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      final response = await ApiService.post('/api/user/login', {'phone': normalizedPhone, 'otp': otp, 'reqId': reqId});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': data['success'] == true, 'user': data['user'], 'token': data['token'], 'needsRegistration': data['needsRegistration']};
      }
      return {'success': false, 'message': 'Login failed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> registerUser({required String phone, required String otp, required String? reqId, required String name, required String gender}) async {
    try {
      final normalizedPhone = PhoneUtils.normalize(phone) ?? phone;
      final response = await ApiService.post('/api/user/register', {'phone': normalizedPhone, 'otp': otp, 'reqId': reqId, 'name': name, 'gender': gender});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': data['success'] == true, 'user': data['user'], 'token': data['token']};
      }
      return {'success': false, 'message': 'Registration failed'};
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
