import 'dart:developer' as developer;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'shared_prefs.dart';

class AuthService {
  // Server API URLs
  static const String _serverBaseUrl = 'http://20.55.49.93:8000';
  static const String _loginUrl = '$_serverBaseUrl/api/login/';
  static const String _registerUrl = '$_serverBaseUrl/api/register/';

  // Login functionality - connect to Django server
  static Future<bool> login(String email, String password) async {
    try {
      developer.log('Attempting login with: $email to server');

      // Send login request to Django server
      final response = await http
          .post(
            Uri.parse(_loginUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      developer.log('Login response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Parse response data
        final data = json.decode(response.body);
        developer.log('Login successful for: $email');

        // Save user data in shared preferences
        await SharedPrefs.setLoggedIn(true);
        await SharedPrefs.setEmail(email);

        // Save additional user data if available
        if (data.containsKey('name')) {
          await SharedPrefs.setName(data['name'] ?? '');
        }

        if (data.containsKey('token')) {
          await SharedPrefs.setToken(data['token']);
        }

        return true;
      }

      developer.log('Login failed for: $email - ${response.body}');
      return false;
    } catch (e) {
      developer.log('Error during login: $e');
      return false;
    }
  }

  // Registration functionality - connect to Django server
  static Future<bool> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      developer.log('Registering new user on server: $email, $name');

      // Send registration request to Django server
      final response = await http
          .post(
            Uri.parse(_registerUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      developer.log('Registration response status: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Parse response data
        final data = json.decode(response.body);
        developer.log('User registered successfully: $email');

        // Auto login after registration
        await SharedPrefs.setLoggedIn(true);
        await SharedPrefs.setEmail(email);
        await SharedPrefs.setName(name);

        // Save token if provided
        if (data.containsKey('token')) {
          await SharedPrefs.setToken(data['token']);
        }

        return true;
      }

      developer.log('Registration failed: ${response.body}');
      return false;
    } catch (e) {
      developer.log('Error during registration: $e');
      return false;
    }
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    return SharedPrefs.isLoggedIn();
  }

  // Logout functionality
  static Future<void> logout() async {
    developer.log('Logging out user');
    await SharedPrefs.clear();
  }

  // Get current user info
  static Future<Map<String, String>> getCurrentUser() async {
    final email = await SharedPrefs.getEmail();
    final name = await SharedPrefs.getName();
    final token = await SharedPrefs.getToken();

    return {'email': email, 'name': name, 'token': token};
  }
}
