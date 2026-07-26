import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiResponse<T> {
  final T? data;
  final String? error;
  final int statusCode;

  ApiResponse({this.data, this.error, required this.statusCode});

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class ApiService {
  static const String baseUrl = 'https://lulu.sarkarivle.org';
  static const String mediaToken = 'GOGO_SECURE_ACCESS_2024_PROD';

  static String getSecureUrl(String? url) {
    if (url == null || url.isEmpty || url == 'null') return '';
    
    String finalUrl = url;
    if (!finalUrl.startsWith('http')) {
      finalUrl = '$baseUrl$finalUrl';
    }
    
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
    } on SocketException {
      throw 'No Internet connection';
    } on TimeoutException {
      throw 'Connection timed out';
    } catch (e) {
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    final url = '$baseUrl$endpoint';
    try {
      final headers = await _getHeaders();
      debugPrint('🌐 GET: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 401) {
        _handleUnauthorized();
      }
      
      return response;
    } on SocketException {
      throw 'No Internet connection';
    } on TimeoutException {
      throw 'Connection timed out';
    } catch (e) {
      rethrow;
    }
  }

  static void _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    // We can use a Stream or EventBus to trigger UI logout
  }
  
  static Future<http.StreamedResponse> multipart(String endpoint, String filePath, String fieldName, Map<String, String> fields) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      var headers = await _getHeaders();
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      request.fields.addAll(fields);
      return await request.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      rethrow;
    }
  }
}
