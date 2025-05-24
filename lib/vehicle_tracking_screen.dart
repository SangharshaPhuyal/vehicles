import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:math';
import 'notification_screen.dart';

class VehicleTrackingScreen extends StatefulWidget {
  const VehicleTrackingScreen({super.key});

  @override
  State<VehicleTrackingScreen> createState() => _VehicleTrackingScreenState();
}

class _VehicleTrackingScreenState extends State<VehicleTrackingScreen>
    with AutomaticKeepAliveClientMixin {
  bool isLoading = false;
  bool isConnected = false;
  String error = '';
  Map<String, dynamic> vehicleData = {};
  Timer? _refreshTimer;
  bool outsideGeofence = false;
  bool theftAlertSent = false;

  // Track previous alert state
  bool _previousAlertState = false;
  DateTime? _lastAlertTime;

  // Helper method to properly check if alert is true
  bool _isAlertTrue(dynamic alertValue) {
    // Handle various ways alert might be represented: boolean true, string "true", or number 1
    if (alertValue is bool) {
      return alertValue;
    } else if (alertValue is String) {
      return alertValue.toLowerCase() == 'true';
    } else if (alertValue is num) {
      return alertValue > 0;
    }
    return false;
  }

  // Geofence parameters
  final double centerLat = 27.6968;
  final double centerLng = 85.2663;
  final double geofenceRadiusKm = 1.0; // 1km radius

  // Server connection settings
  final String baseUrl = 'http://20.55.49.93:8000/api/status/';

  @override
  void initState() {
    super.initState();
    // Fetch data immediately when screen opens
    fetchVehicleData();

    // Set up automatic refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      fetchVehicleData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  // Fetch vehicle data from Django server
  Future<void> fetchVehicleData() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    // Use a client with proper connection handling
    final client = http.Client();

    try {
      developer.log('Fetching vehicle data from: $baseUrl');

      final response = await client
          .get(Uri.parse(baseUrl), headers: {'Connection': 'keep-alive'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Successfully got data
        final data = json.decode(response.body);
        developer.log('Fetched data successfully: $data');

        // Store previous geofence status to detect changes
        final bool wasOutsideGeofence = outsideGeofence;

        // Update state with vehicle data
        setState(() {
          vehicleData = data;
          isLoading = false;
          isConnected = true;
          error = '';

          // Check if outside geofence
          if (data.containsKey('latitude') && data.containsKey('longitude')) {
            double lat = double.parse(data['latitude'].toString());
            double lng = double.parse(data['longitude'].toString());

            outsideGeofence = checkIfOutsideGeofence(lat, lng);

            // If outside geofence status just changed, send theft alert to server
            if (outsideGeofence && !wasOutsideGeofence) {
              sendTheftDetectionToServer(lat, lng);
            }
          }
        });

        // Only check for accident alert if explicitly true (exact boolean comparison)
        final bool currentAlert = _isAlertTrue(data['alert']);
        final DateTime now = DateTime.now();

        // Only show notification if:
        // 1. Alert is true AND
        // 2. Previous state was false (state change) AND
        // 3. Either no previous alert time OR at least 30 seconds have passed since last alert
        if (currentAlert &&
            !_previousAlertState &&
            (_lastAlertTime == null ||
                now.difference(_lastAlertTime!) >
                    const Duration(seconds: 30))) {
          developer.log(
            'ALERT STATE CHANGED: false -> true. Showing notification.',
          );
          final String location =
              '${data['latitude'] ?? '0'}, ${data['longitude'] ?? '0'}';
          NotificationService.handleAccidentNotification(
            context,
            true,
            location,
          );
          _lastAlertTime = now;
        }
        _previousAlertState = currentAlert;
      } else {
        setState(() {
          isLoading = false;
          isConnected = false;
          error = 'Server returned status code: ${response.statusCode}';
        });
      }
    } catch (e) {
      developer.log('Error fetching vehicle data: $e');
      setState(() {
        isLoading = false;
        isConnected = false;
        error = e.toString();
      });
    } finally {
      // Always properly close the client
      client.close();
    }
  }

  // Check if location is outside geofence
  bool checkIfOutsideGeofence(double lat, double lng) {
    // Convert radius to approximate degree distance (very rough estimate)
    // More accurate would be to use the haversine formula
    double radius = geofenceRadiusKm / 111.0; // 1 degree is roughly 111km

    double distance = sqrt(pow(lat - centerLat, 2) + pow(lng - centerLng, 2));
    return distance > radius;
  }

  // Send theft detection to server when vehicle is outside geofence
  Future<void> sendTheftDetectionToServer(double lat, double lng) async {
    try {
      // Get the license plate if available
      final String licensePlate = vehicleData['license_plate'] ?? 'Unknown';

      // Create API URL for theft detection
      final url = Uri.parse(baseUrl);

      // Get vehicle data to send
      final data = {
        'license_plate': licensePlate,
        'latitude': lat,
        'longitude': lng,
        'theft': true, // Mark this as theft detection
        'alert':
            vehicleData['alert'] ?? false, // Preserve existing accident status
      };

      developer.log('Sending theft detection to server: ${jsonEncode(data)}');

      // Use client for better connection handling
      final client = http.Client();
      try {
        // Send the theft detection data
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

        if (response.statusCode == 200 || response.statusCode == 201) {
          developer.log('Theft detection sent successfully: ${response.body}');
          setState(() {
            theftAlertSent = true;
          });
        } else {
          developer.log(
            'Error sending theft detection: ${response.statusCode} - ${response.body}',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      developer.log('Exception when sending theft detection: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Tracking'),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Vehicle Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? Colors.green : Colors.red,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    isConnected
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.red.withOpacity(0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Alert banner - show only when alert is true
                    if (vehicleData.isNotEmpty &&
                        _isAlertTrue(vehicleData['alert'])) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Alert! Vehicle may be in danger.',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (vehicleData.isNotEmpty) ...[
                      // Location information with icon
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${vehicleData['latitude'] ?? '0'}, ${vehicleData['longitude'] ?? '0'}',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Last update with icon
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            color: Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Updated: ${vehicleData['timestamp'] ?? 'Unknown'}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Geofence status pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  outsideGeofence
                                      ? Colors.orange.shade100
                                      : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    outsideGeofence
                                        ? Colors.orange
                                        : Colors.green,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  outsideGeofence
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline,
                                  color:
                                      outsideGeofence
                                          ? Colors.orange
                                          : Colors.green,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  outsideGeofence
                                      ? 'Outside Geofence'
                                      : 'Inside Geofence',
                                  style: TextStyle(
                                    color:
                                        outsideGeofence
                                            ? Colors.orange.shade800
                                            : Colors.green.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : fetchVehicleData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon:
                            isLoading
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.refresh),
                        label: Text(isLoading ? 'LOADING...' : 'REFRESH'),
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
