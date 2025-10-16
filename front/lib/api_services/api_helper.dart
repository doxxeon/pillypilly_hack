import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'token_service.dart';

class ApiHelper {
  static final AuthService _auth = AuthService();
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? '';

  /// ✅ 토큰 포함 헤더 자동 구성
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await _auth.getValidToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// ✅ GET 요청
  static Future<http.Response> get(String endpoint) async {
    final headers = await getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    return http.get(uri, headers: headers);
  }

  /// ✅ POST 요청
  static Future<http.Response> post(String endpoint, dynamic body) async {
    final headers = await getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    return http.post(uri, headers: headers, body: jsonEncode(body));
  }
}