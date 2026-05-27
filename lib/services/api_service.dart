import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://api.gogodatings.com';
  static const String mediaToken = 'GOGO_SECURE_ACCESS_2024_PROD';

  /// Wraps a media URL with a security token for access
  static String getSecureUrl(String? url) {
    if (url == null || url.isEmpty || url == 'null') return '';
    
    String finalUrl = url;
    if (!finalUrl.startsWith('http')) {
      // Handle relative paths if any
      finalUrl = '$baseUrl$finalUrl';
    }
    
    // Check if it's our server's media and not already tokenized
    if (finalUrl.contains(baseUrl) && !finalUrl.contains('token=')) {
      final separator = finalUrl.contains('?') ? '&' : '?';
      return '$finalUrl${separator}token=$mediaToken';
    }
    return finalUrl;
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-gogo-secret': mediaToken,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final url = '$baseUrl$endpoint';
    try {
      final headers = await _getHeaders();
      debugPrint('🚀 POST: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 401) {
        _handleUnauthorized();
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    final url = '$baseUrl$endpoint';
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 401) {
        _handleUnauthorized();
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static void _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    // Navigate to login if context is available via a navigator key or stream
  }
  
  static Future<http.StreamedResponse> multipart(String endpoint, String filePath, String fieldName, Map<String, String> fields) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      var headers = await _getHeaders();
      headers.remove('Content-Type'); // Let MultipartRequest set the correct boundary
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      request.fields.addAll(fields);
      return await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      rethrow;
    }
  }
}
