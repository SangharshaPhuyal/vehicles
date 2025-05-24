import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

class SharedPrefs {
  // Keys
  static const String _keyLoggedIn = 'isLoggedIn';
  static const String _keyEmail = 'userEmail';
  static const String _keyName = 'userName';
  static const String _keyVehicleId = 'vehicleId';
  static const String _keyServerUrl = 'serverUrl';
  static const String _keyAutoConnect = 'autoConnect';
  static const String _keyToken = 'userToken';

  // Get the logged in state
  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyLoggedIn) ?? false;
    } catch (e) {
      developer.log('Error checking login state: $e');
      return false;
    }
  }

  // Set the logged in state
  static Future<void> setLoggedIn(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLoggedIn, value);
    } catch (e) {
      developer.log('Error setting login state: $e');
    }
  }

  // Get the user email
  static Future<String> getEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyEmail) ?? '';
    } catch (e) {
      developer.log('Error getting email: $e');
      return '';
    }
  }

  // Set the user email
  static Future<void> setEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEmail, email);
    } catch (e) {
      developer.log('Error setting email: $e');
    }
  }

  // Get the user name
  static Future<String> getName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyName) ?? '';
    } catch (e) {
      developer.log('Error getting name: $e');
      return '';
    }
  }

  // Set the user name
  static Future<void> setName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyName, name);
    } catch (e) {
      developer.log('Error setting name: $e');
    }
  }

  // Get the vehicle ID
  static Future<String> getVehicleId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyVehicleId) ?? '';
    } catch (e) {
      developer.log('Error getting vehicle ID: $e');
      return '';
    }
  }

  // Set the vehicle ID
  static Future<void> setVehicleId(String vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyVehicleId, vehicleId);
    } catch (e) {
      developer.log('Error setting vehicle ID: $e');
    }
  }

  // Get the server URL
  static Future<String> getServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyServerUrl) ?? 'http://20.55.49.93:8000/api';
    } catch (e) {
      developer.log('Error getting server URL: $e');
      return 'http://20.55.49.93:8000/api';
    }
  }

  // Set the server URL
  static Future<void> setServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyServerUrl, url);
    } catch (e) {
      developer.log('Error setting server URL: $e');
    }
  }

  // Get auto-connect setting
  static Future<bool> getAutoConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoConnect) ?? true;
    } catch (e) {
      developer.log('Error getting auto-connect setting: $e');
      return true;
    }
  }

  // Set auto-connect setting
  static Future<void> setAutoConnect(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoConnect, value);
    } catch (e) {
      developer.log('Error setting auto-connect: $e');
    }
  }

  // Get the auth token
  static Future<String> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyToken) ?? '';
    } catch (e) {
      developer.log('Error getting token: $e');
      return '';
    }
  }

  // Set the auth token
  static Future<void> setToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyToken, token);
    } catch (e) {
      developer.log('Error setting token: $e');
    }
  }

  // Clear all preferences (for logout)
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep server URL and vehicle ID even after logout
      final serverUrl = await getServerUrl();
      final vehicleId = await getVehicleId();
      final autoConnect = await getAutoConnect();

      await prefs.clear();

      // Restore settings that should persist
      await setServerUrl(serverUrl);
      await setVehicleId(vehicleId);
      await setAutoConnect(autoConnect);

      // Ensure token is cleared for security
      await prefs.remove(_keyToken);
    } catch (e) {
      developer.log('Error clearing preferences: $e');
    }
  }
}
