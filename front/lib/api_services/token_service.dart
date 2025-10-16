import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  String get baseUrl => dotenv.env['API_BASE_URL'] ?? '';

  static const String tokenKey = 'jwt_token';           // access
  static const String refreshKey = 'jwt_refresh_token'; // refresh
  static const String userIdKey = 'user_id';            // 서버가 주는 user_id

  bool _isExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = (payload['exp'] as num?)?.toInt();
      if (exp == null) return true;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= exp;
    } catch (_) {
      return true;
    }
  }

  Future<bool> fetchToken() async {
    final url = Uri.parse('$baseUrl/auth/token');
    final res = await http.post(url);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final access = (data['token'] ?? data['access_token']) as String?;
      final refresh = data['refresh_token'] as String?;
      final userId = data['user_id'] as String?;
      if (access == null || refresh == null || userId == null) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, access);
      await prefs.setString(refreshKey, refresh);
      await prefs.setString(userIdKey, userId);
      return true;
    }
    return false;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(refreshKey);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(userIdKey);
  }

  Future<String?> refreshAccessToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null) return null;

    final url = Uri.parse('$baseUrl/auth/refresh');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refresh}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final access = (data['token'] ?? data['access_token']) as String?;
      final newRefresh = data['refresh_token'] as String?;
      final userId = data['user_id'] as String?;
      if (access == null || newRefresh == null || userId == null) return null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, access);
      await prefs.setString(refreshKey, newRefresh);
      await prefs.setString(userIdKey, userId);
      return access;
    }
    return null;
  }

  Future<String?> getValidToken() async {
    final access = await getToken();
    if (access == null || _isExpired(access)) {
      // ✅ refresh만 호출
      return await refreshAccessToken();  // 실패하면 null
    }
    return access;
  }
}
