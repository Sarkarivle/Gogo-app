import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/media_service.dart';

class VerificationRepository {
  static final VerificationRepository _instance = VerificationRepository._internal();
  factory VerificationRepository() => _instance;
  VerificationRepository._internal();

  Future<bool> submitVerification({required File image, required String phone}) async {
    try {
      // Compress before upload for a faster, lighter submission.
      final File compressedImage = await MediaService().compressImage(image);

      final encodedPhone = Uri.encodeComponent(phone);
      final url = '${ApiService.baseUrl}/api/chat/upload?phone=$encodedPhone';

      var request = http.MultipartRequest('POST', Uri.parse(url));
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      request.headers['Accept'] = 'application/json';
      request.headers['x-gogo-secret'] = ApiService.mediaToken;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';

      request.fields['phone'] = phone;
      request.fields['type'] = 'verification';
      request.files.add(await http.MultipartFile.fromPath('image', compressedImage.path));
      
      var streamedRes = await request.send().timeout(const Duration(seconds: 40));
      var res = await http.Response.fromStream(streamedRes);
      
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        String selfieUrl = ApiService.getSecureUrl(data['imageUrl']);

        // Submit verification request using protected ApiService
        final response = await ApiService.post('/api/user/verify-request', {
          'phone': phone,
          'selfieUrl': selfieUrl
        });

        if (response.statusCode == 200) {
          // Update local status to reflect submission
          final userData = UserRepository().currentUser;
          if (userData != null) {
            Map<String, dynamic> updated = Map.from(userData);
            updated['verificationSubmitted'] = true;
            await UserRepository().updateLocalUser(updated);
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Verification upload error: $e');
      return false;
    }
  }
}
