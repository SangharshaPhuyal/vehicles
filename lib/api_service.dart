import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:developer' as developer;

class ApiService {
  static const String baseUrl = 'http://20.55.49.93:8000/api';

  // Function to fetch vehicle data from server
  static Future<Map<String, dynamic>> getVehicleData(
    String licensePlate,
  ) async {
    final url = Uri.parse('$baseUrl/vehicle/$licensePlate/');

    try {
      developer.log('Fetching vehicle data for $licensePlate from $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        // Successfully got data
        final data = json.decode(response.body);
        developer.log('Vehicle data received: $data');
        return data;
        // This will contain: license_plate, latitude, longitude, timestamp, alert
      } else {
        developer.log(
          'Error fetching data: ${response.statusCode} - ${response.body}',
        );
        return {};
      }
    } catch (e) {
      developer.log('Exception when fetching data: $e');
      return {};
    }
  }

  // Function to send theft alert to server
  static Future<bool> sendTheftAlert(
    String licensePlate,
    double latitude,
    double longitude,
  ) async {
    final url = Uri.parse('$baseUrl/theft-alert/');

    try {
      developer.log(
        'Sending theft alert for $licensePlate at $latitude, $longitude',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'license_plate': licensePlate,
          'latitude': latitude,
          'longitude': longitude,
          // Current time will be added by server
        }),
      );

      if (response.statusCode == 200) {
        developer.log('Theft alert sent successfully');
        return true;
      } else {
        developer.log(
          'Error sending theft alert: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      developer.log('Exception when sending theft alert: $e');
      return false;
    }
  }

  // Function to update vehicle location with theft or alert status
  static Future<bool> updateVehicleStatus(
    String licensePlate,
    double latitude,
    double longitude, {
    bool alert = false,
    bool theft = false,
  }) async {
    final url = Uri.parse('$baseUrl/status/');

    try {
      final Map<String, dynamic> data = {
        'license_plate': licensePlate,
        'latitude': latitude,
        'longitude': longitude,
        'alert': alert,
        'theft': theft,
      };

      developer.log(
        'Updating vehicle status for $licensePlate: ${jsonEncode(data)}',
      );

      // Use a client for better connection handling
      final client = http.Client();
      try {
        final response = await client
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Connection': 'keep-alive',
              },
              body: jsonEncode(data),
            )
            .timeout(const Duration(seconds: 5));

        final bool success =
            response.statusCode == 200 || response.statusCode == 201;

        if (success) {
          developer.log('Vehicle status update successful');
        } else {
          developer.log(
            'Vehicle status update failed: ${response.statusCode} - ${response.body}',
          );
        }

        return success;
      } finally {
        client.close();
      }
    } catch (e) {
      developer.log('Error updating vehicle status: $e');
      return false;
    }
  }

  // Example function to check if location is outside permitted area
  static bool checkIfOutsideGeofence(
    double lat,
    double lng, {
    double centerLat = 27.6968,
    double centerLng = 85.2663,
    double radiusKm = 1.0,
  }) {
    // Convert radius to approximate degree distance (very rough estimate)
    // More accurate would be to use the haversine formula
    double radius = radiusKm / 111.0; // 1 degree is roughly 111km

    double distance = sqrt(pow(lat - centerLat, 2) + pow(lng - centerLng, 2));
    return distance > radius;
  }
}
