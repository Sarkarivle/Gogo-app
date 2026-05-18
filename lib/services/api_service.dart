import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use the exact IP and Port
  static const String baseUrl = 'http://72.61.170.181:5000';

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    try {
      return await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    try {
      return await http.get(Uri.parse('$baseUrl$endpoint'))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      rethrow;
    }
  }
}
