import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'dart:async';
import 'notification_screen.dart';

class DjangoTrackingScreen extends StatefulWidget {
  const DjangoTrackingScreen({super.key});

  @override
  State<DjangoTrackingScreen> createState() => _DjangoTrackingScreenState();
}

class _DjangoTrackingScreenState extends State<DjangoTrackingScreen>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  bool isConnecting = false;
  bool isConnected = false;
  String error = '';
  Timer? _refreshTimer;
  final List<LatLng> _routePoints = [];

  // Vehicle location data
  double latitude = 27.7;
  double longitude = 85.3;
  String licensePlate = 'Unknown';
  String lastUpdate = '';
  bool alertStatus = false;
  bool theftStatus = false;

  // Track previous alert states globally to preserve across tab switches
  static bool previousAlertStatus = false;
  static bool previousTheftStatus = false;

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

  // Server connection settings - Updated with new simplified API
  final String apiStatusUrl = 'http://20.55.49.93:8000/api/status/';

  @override
  bool get wantKeepAlive => true; // Keep the state when switching tabs

  @override
  void initState() {
    super.initState();

    // Initialize alert statuses to false explicitly
    alertStatus = false;
    theftStatus = false;

    // Connect to Django on start to get vehicle location
    getVehicleStatusFromServer();

    // Set up automatic refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        getVehicleStatusFromServer();
      }
    });

    developer.log('DjangoTrackingScreen initialized');
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Get vehicle status data from Django server using the simplified API
  Future<void> getVehicleStatusFromServer() async {
    if (isConnecting) return; // Prevent multiple simultaneous requests

    setState(() {
      isConnecting = true;
    });

    // Create a reusable client with proper connection handling
    final client = http.Client();

    try {
      developer.log('Getting vehicle status from Django: $apiStatusUrl');

      // Using GET request with connection keepalive header
      final response = await client
          .get(Uri.parse(apiStatusUrl), headers: {'Connection': 'keep-alive'})
          .timeout(const Duration(seconds: 5));

      developer.log('Response status: ${response.statusCode}');
      developer.log('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Connection successful
        Map<String, dynamic> data;
        try {
          data = json.decode(response.body);
          developer.log('Successfully parsed response: $data');
        } catch (e) {
          setState(() {
            isConnecting = false;
            error = 'Error parsing response: $e';
          });
          developer.log('Error parsing JSON response: $e');
          return;
        }

        developer.log('Received vehicle data: $data');

        // Parse location data
        try {
          // Get latitude and longitude
          double lat = latitude;
          double lng = longitude;

          // Try to extract latitude
          if (data.containsKey('latitude')) {
            try {
              lat = double.parse(data['latitude'].toString());
              developer.log('Parsed latitude from server: $lat');
            } catch (e) {
              developer.log(
                'Error parsing latitude from server: ${data['latitude']} - $e',
              );
            }
          }

          // Try to extract longitude
          if (data.containsKey('longitude')) {
            try {
              lng = double.parse(data['longitude'].toString());
              developer.log('Parsed longitude from server: $lng');
            } catch (e) {
              developer.log(
                'Error parsing longitude from server: ${data['longitude']} - $e',
              );
            }
          }

          // Get license plate
          String plate = licensePlate;
          if (data.containsKey('license_plate')) {
            plate = data['license_plate'] ?? licensePlate;
          }

          // Check for alert status (accident) - strict boolean comparison
          bool alert = _isAlertTrue(data['alert']);

          // Debug the actual alert value to see what the server is sending
          developer.log(
            'Raw alert value from server: ${data['alert']} (${data['alert'].runtimeType})',
          );
          developer.log('Parsed alert status: $alert');

          // Check for theft status - strict boolean comparison
          bool theft = _isAlertTrue(data['theft']);

          // Debug the theft value
          developer.log(
            'Raw theft value from server: ${data['theft']} (${data['theft']?.runtimeType})',
          );
          developer.log('Parsed theft status: $theft');

          // Get timestamp or last_updated if available
          String timestamp = '';
          if (data.containsKey('last_updated')) {
            timestamp = data['last_updated'] ?? '';
          } else if (data.containsKey('timestamp')) {
            timestamp = data['timestamp'] ?? '';
            // Format timestamp for display if needed
            try {
              DateTime dateTime = DateTime.parse(timestamp);
              timestamp = dateTime.toString().substring(
                0,
                19,
              ); // YYYY-MM-DD HH:MM:SS
            } catch (e) {
              developer.log('Error parsing timestamp: $e');
              timestamp = '';
            }
          }

          // Update state with new values
          setState(() {
            isConnecting = false;
            isConnected = true;
            error = '';

            // Update vehicle location and status
            latitude = lat;
            longitude = lng;
            licensePlate = plate;
            alertStatus = alert;
            theftStatus = theft;
            lastUpdate =
                timestamp.isNotEmpty
                    ? timestamp
                    : DateTime.now().toString().substring(
                      0,
                      19,
                    ); // YYYY-MM-DD HH:MM:SS

            // Add to route points if not duplicate
            if (_routePoints.isEmpty ||
                (_routePoints.last.latitude != lat ||
                    _routePoints.last.longitude != lng)) {
              _routePoints.add(LatLng(lat, lng));
              // Keep only last 20 points to avoid clutter
              if (_routePoints.length > 20) {
                _routePoints.removeAt(0);
              }
            }
          });

          // Center map on vehicle location
          _mapController.move(LatLng(lat, lng), 15.0);

          // Log previous and current states for debugging
          developer.log(
            'Previous alert status: $previousAlertStatus, Current: $alert',
          );
          developer.log(
            'Previous theft status: $previousTheftStatus, Current: $theft',
          );

          // Only show notifications if alerts have CHANGED from false to true
          // This prevents notifications when app opens with existing alert states or on every update
          if (alert && !previousAlertStatus) {
            developer.log(
              '⚠️ ALERT CHANGED: false -> true. Showing notification.',
            );
            NotificationService.handleAccidentNotification(
              context,
              true,
              'Accident detected for vehicle $plate',
            );
          }

          if (theft && !previousTheftStatus) {
            developer.log(
              '⚠️ THEFT CHANGED: false -> true. Showing notification.',
            );
            NotificationService.handleTheftNotification(
              context,
              true,
              'Theft detected for vehicle $plate',
            );
          }

          // Update static previous states for next check
          previousAlertStatus = alert;
          previousTheftStatus = theft;
        } catch (e) {
          setState(() {
            isConnecting = false;
            error = 'Error processing location data: $e';
          });
          developer.log('Error processing location data: $e');
        }
      } else {
        setState(() {
          isConnecting = false;
          isConnected = false;
          error =
              'Server returned status code: ${response.statusCode} - ${response.body}';
        });
        developer.log(
          'Server error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      developer.log('Connection error: $e');
      setState(() {
        isConnecting = false;
        isConnected = false;
        error = e.toString();
      });
    } finally {
      // Always close the client to prevent resource leaks
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isConnecting ? null : getVehicleStatusFromServer,
            tooltip: 'Refresh location',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status indicator bar
          Container(
            color:
                theftStatus
                    ? Colors.red.shade100
                    : (alertStatus
                        ? Colors.orange.shade100
                        : Colors.green.shade100),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  theftStatus
                      ? Icons.warning_amber
                      : (alertStatus ? Icons.car_crash : Icons.check_circle),
                  color:
                      theftStatus
                          ? Colors.red
                          : (alertStatus ? Colors.orange : Colors.green),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    theftStatus
                        ? 'Theft Alert: Vehicle may be stolen!'
                        : (alertStatus
                            ? 'Accident Alert: Vehicle accident detected!'
                            : 'Status Normal: Vehicle operating safely'),
                    style: TextStyle(
                      color:
                          theftStatus
                              ? Colors.red.shade800
                              : (alertStatus
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error message if any
          if (error.isNotEmpty)
            Container(
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Map with vehicle location
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(latitude, longitude),
                    initialZoom: 15.0,
                    interactionOptions: const InteractionOptions(
                      enableMultiFingerGestureRace: true,
                      flags: InteractiveFlag.all,
                    ),
                    keepAlive: true,
                    onMapReady: () {
                      developer.log('Map is ready to display');
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                      subdomains: const ['a', 'b', 'c'],
                      additionalOptions: const {
                        'attribution': '© OpenStreetMap contributors',
                      },
                      fallbackUrl:
                          'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                      errorImage: NetworkImage(
                        'https://cdn.jsdelivr.net/gh/flutter_map/flutter_map@master/tile_error_image.png',
                      ),
                      maxNativeZoom: 19,
                      maxZoom: 19,
                      tileProvider: NetworkTileProvider(),
                    ),

                    // Route polyline
                    if (_routePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 4.0,
                            color: Colors.blue.withOpacity(0.7),
                          ),
                        ],
                      ),

                    // Marker for current position
                    MarkerLayer(
                      markers: [
                        // Vehicle position marker
                        Marker(
                          width: 40.0,
                          height: 40.0,
                          point: LatLng(latitude, longitude),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  theftStatus
                                      ? Colors.red.withOpacity(0.6)
                                      : (alertStatus
                                          ? Colors.orange.withOpacity(0.6)
                                          : Colors.blue.withOpacity(0.5)),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Loading indicator
                if (isConnecting)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ),

                // Vehicle info overlay
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            licensePlate,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (lastUpdate.isNotEmpty)
                            Text(
                              'Last update: $lastUpdate',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _mapController.move(LatLng(latitude, longitude), 15.0);
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}
