import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://72.61.170.181';

  static Future<Map<String, String>> _getHeaders() async {
    // Add auth token if available in the future
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final url = '$baseUrl$endpoint';
    try {
      final headers = await _getHeaders();
      print('🚀 POST: $url');
      print('📦 Body: ${jsonEncode(body)}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30)); // Increased to 30s
      
      print('✅ Response [${response.statusCode}]: ${response.body}');
      return response;
    } on SocketException catch (e) {
      print('❌ SocketException: $e');
      throw Exception('Server unreachable. Please check if your VPS Firewall allows Port 5000 at $baseUrl');
    } on TimeoutException {
      print('❌ TimeoutException at $url');
      throw Exception('Connection timed out. Server is not responding. Check PM2 logs on VPS.');
    } catch (e) {
      print('❌ Error at $url: $e');
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    final url = '$baseUrl$endpoint';
    try {
      final headers = await _getHeaders();
      print('🚀 GET: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 20));
      
      print('✅ Response [${response.statusCode}]');
      return response;
    } on SocketException catch (e) {
      print('❌ SocketException: $e');
      throw Exception('Server unreachable at $baseUrl');
    } on TimeoutException {
      print('❌ TimeoutException at $url');
      throw Exception('Connection timed out');
    } catch (e) {
      print('❌ Error at $url: $e');
      rethrow;
    }
  }
  
  static Future<http.StreamedResponse> multipart(String endpoint, String filePath, String fieldName, Map<String, String> fields) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      request.fields.addAll(fields);
      return await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      rethrow;
    }
  }
}
