import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://72.61.170.181:5000';

  static Future<Map<String, String>> _getHeaders() async {
    // Add auth token if available in the future
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final headers = await _getHeaders();
      return await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
    } on SocketException {
      throw Exception('No Internet connection');
    } catch (e) {
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    try {
      final headers = await _getHeaders();
      return await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
    } on SocketException {
      throw Exception('No Internet connection');
    } catch (e) {
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
