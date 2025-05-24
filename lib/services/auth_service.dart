import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String baseUrl = 'http://your-api-base-url';
  static const String tokenKey = 'auth_token';

  final SharedPreferences _prefs;

  AuthService(this._prefs);

  Future<User> signup({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/signup/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        final userData = jsonDecode(response.body);
        final user = User.fromJson(userData);
        if (user.token != null) {
          await _prefs.setString(tokenKey, user.token!);
        }
        return user;
      } else {
        throw Exception('Signup failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to signup: $e');
    }
  }

  Future<User> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        final user = User.fromJson(userData);
        if (user.token != null) {
          await _prefs.setString(tokenKey, user.token!);
        }
        return user;
      } else {
        throw Exception('Login failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to login: $e');
    }
  }

  Future<void> logout() async {
    try {
      final token = _prefs.getString(tokenKey);
      if (token != null) {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      }
    } finally {
      await _prefs.remove(tokenKey);
    }
  }

  Future<String?> getToken() async {
    return _prefs.getString(tokenKey);
  }

  Future<bool> isLoggedIn() async {
    return await getToken() != null;
  }
} 