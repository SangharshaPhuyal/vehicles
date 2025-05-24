import 'dart:convert';
import 'package:http/http.dart' as http;

// Vehicle API service class
class VehicleApiService {
  // Change this to your server's IP address or domain
  final String baseUrl = 'http://20.55.49.93:8000';

  // Get data for a specific vehicle
  Future<Vehicle> getVehicleData(String licensePlate) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/vehicle/$licensePlate/'),
    );

    if (response.statusCode == 200) {
      return Vehicle.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load vehicle data: ${response.body}');
    }
  }

  // Get data for all vehicles
  Future<List<Vehicle>> getAllVehicles() async {
    final response = await http.get(Uri.parse('$baseUrl/api/vehicle/'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> vehiclesJson = data['vehicles'];
      return vehiclesJson.map((json) => Vehicle.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load vehicles');
    }
  }

  // Send theft alert
  Future<bool> sendTheftAlert(
    String licensePlate,
    double latitude,
    double longitude,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/status/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'license_plate': licensePlate,
        'latitude': latitude,
        'longitude': longitude,
        'theft': true,
      }),
    );

    return response.statusCode == 200 || response.statusCode == 201;
  }

  // Update vehicle status with theft and/or alert
  Future<bool> updateVehicleStatus(
    String licensePlate,
    double latitude,
    double longitude, {
    bool alert = false,
    bool theft = false,
  }) async {
    // Use a client for better connection handling
    final client = http.Client();

    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/status/'),
        headers: {
          'Content-Type': 'application/json',
          'Connection': 'keep-alive',
        },
        body: json.encode({
          'license_plate': licensePlate,
          'latitude': latitude,
          'longitude': longitude,
          'alert': alert,
          'theft': theft,
        }),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } finally {
      client.close();
    }
  }
}

// Vehicle model class
class Vehicle {
  final String licensePlate;
  final double latitude;
  final double longitude;
  final bool alert;
  final String timestamp;

  Vehicle({
    required this.licensePlate,
    required this.latitude,
    required this.longitude,
    required this.alert,
    required this.timestamp,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Helper function to properly parse alert value
    bool parseAlertValue(dynamic alertValue) {
      if (alertValue is bool) {
        return alertValue;
      } else if (alertValue is String) {
        return alertValue.toLowerCase() == 'true';
      } else if (alertValue is num) {
        return alertValue > 0;
      }
      return false;
    }

    return Vehicle(
      licensePlate: json['license_plate'],
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      alert: parseAlertValue(json['alert']),
      timestamp: json['timestamp'] ?? '',
    );
  }
}
