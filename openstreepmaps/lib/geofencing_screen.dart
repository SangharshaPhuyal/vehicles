import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'notification_screen.dart'; // Import the notification screen

class GeofencingScreen extends StatefulWidget {
  const GeofencingScreen({super.key});

  @override
  _GeofencingScreenState createState() => _GeofencingScreenState();
}

class _GeofencingScreenState extends State<GeofencingScreen>
    with AutomaticKeepAliveClientMixin {
  // Map controller
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // AWS Django server settings
  final String _serverUrl =
      'http://20.55.49.93:8000/api/status/'; // Updated to use the new status endpoint
  Timer? _serverTimer;

  // Location data
  LatLng _serverLocation = const LatLng(0, 0);
  bool _isLocationReady = false;
  String _error = '';
  DateTime? _lastUpdate;
  bool _accidentStatus = false;
  String _licensePlate = '';

  // Track previous alert state to avoid duplicate notifications
  static bool _previousAlertState = false;

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

  // Geofence settings
  bool _isGeofenceActive = false;
  LatLng _geofenceCenter = const LatLng(0, 0);
  double _geofenceRadius = 100.0; // Default radius in meters
  bool _isInsideGeofence = true;
  bool _geofenceAlertShown = false;
  final TextEditingController _radiusController = TextEditingController(
    text: '100',
  );

  // Notifications
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadGeofenceSettings();
    _startServerPolling();
  }

  @override
  void dispose() {
    _serverTimer?.cancel();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  // Initialize the notifications plugin
  Future<void> _initializeNotifications() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestSoundPermission: false,
            requestBadgePermission: false,
            requestAlertPermission: false,
          );

      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
    } catch (e) {
      developer.log("Failed to initialize notifications: $e");
      // Continue without notifications if initialization fails
    }
  }

  // Load saved geofence settings
  Future<void> _loadGeofenceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final isGeofenceActive = prefs.getBool('isGeofenceActive') ?? false;
      final double? lat = prefs.getDouble('geofenceLat');
      final double? lng = prefs.getDouble('geofenceLng');
      final double radius = prefs.getDouble('geofenceRadius') ?? 100.0;

      if (lat != null && lng != null) {
        setState(() {
          _isGeofenceActive = isGeofenceActive;
          _geofenceCenter = LatLng(lat, lng);
          _geofenceRadius = radius;
          _radiusController.text = radius.toString();
        });
      }
    } catch (e) {
      developer.log("Error loading geofence settings: $e");
      // Continue with default values if loading fails
    }
  }

  // Save geofence settings
  Future<void> _saveGeofenceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('isGeofenceActive', _isGeofenceActive);
      await prefs.setDouble('geofenceLat', _geofenceCenter.latitude);
      await prefs.setDouble('geofenceLng', _geofenceCenter.longitude);
      await prefs.setDouble('geofenceRadius', _geofenceRadius);

      developer.log("Geofence settings saved");
    } catch (e) {
      developer.log("Error saving geofence settings: $e");
    }
  }

  // Start server data polling
  void _startServerPolling() {
    // Initial fetch
    _fetchServerData();

    // Set up timer for periodic updates (every 5 seconds)
    _serverTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchServerData();
    });
  }

  // Fetch location data from AWS Django server
  Future<void> _fetchServerData() async {
    try {
      // Use a persistent client to handle connections properly
      final client = http.Client();
      try {
        final response = await client
            .get(Uri.parse(_serverUrl), headers: {'Connection': 'keep-alive'})
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Check if the required fields exist in the response
          if (data['latitude'] != null && data['longitude'] != null) {
            try {
              final double lat = double.parse(data['latitude'].toString());
              final double lng = double.parse(data['longitude'].toString());

              // Only consider alert true if explicitly set to true (exact boolean comparison)
              final bool alert = _isAlertTrue(data['alert']);
              final String licensePlate = data['license_plate'] ?? 'Unknown';
              final LatLng newLocation = LatLng(lat, lng);

              setState(() {
                _serverLocation = newLocation;
                _isLocationReady = true;
                _lastUpdate = DateTime.now();
                _error = '';
                // Store old status before updating
                // Update with new status
                _accidentStatus = alert;
                _licensePlate = licensePlate;
              });

              // If this is the first time we're getting location and no geofence is active,
              // use it as the default map center
              if (!_isGeofenceActive &&
                  !_mapReady &&
                  _geofenceCenter.latitude == 0) {
                setState(() {
                  _geofenceCenter = newLocation;
                });

                // Move map to the vehicle location if it's the first update
                if (_mapReady && !_isLocationReady) {
                  _mapController.move(newLocation, 15.0);
                }
              }

              // Check if the vehicle is inside the geofence
              if (_isGeofenceActive) {
                _checkGeofence(newLocation);
              }

              // Only show notification if alert is TRUE and it CHANGED from false to true
              if (alert && !_previousAlertState) {
                developer.log(
                  'ALERT STATE CHANGED: false -> true. Showing notification.',
                );
                NotificationService.showPopupNotification(
                  context,
                  '⚠️ ALERT ⚠️',
                  'Vehicle $licensePlate has reported an alert! Please check immediately.',
                );
              }
              // Update previous alert state for next check
              _previousAlertState = alert;
            } catch (e) {
              setState(() {
                _error = 'Error parsing location data: $e';
              });
              developer.log("Error parsing server data: $e");
            }
          } else {
            setState(() {
              _error = 'No location fields found in data';
            });
            developer.log("Server response missing location fields");
          }
        } else {
          setState(() {
            _error = 'Failed to fetch data: ${response.statusCode}';
          });
          developer.log("Server request failed: ${response.statusCode}");
        }
      } finally {
        // Always close the client to prevent resource leaks
        client.close();
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
      });
      developer.log("Server request error: $e");
    }
  }

  // Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const int earthRadius = 6371000; // Earth radius in meters

    // Convert latitude and longitude from degrees to radians
    final double lat1Rad = point1.latitude * (math.pi / 180);
    final double lng1Rad = point1.longitude * (math.pi / 180);
    final double lat2Rad = point2.latitude * (math.pi / 180);
    final double lng2Rad = point2.longitude * (math.pi / 180);

    // Haversine formula components
    final double dLat = lat2Rad - lat1Rad;
    final double dLng = lng2Rad - lng1Rad;

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    // Calculate the distance
    return earthRadius * c;
  }

  // Check if the vehicle is inside or outside the geofence with improved accuracy
  void _checkGeofence(LatLng location) {
    if (!_isGeofenceActive) return;

    final double distance = _calculateDistance(_geofenceCenter, location);

    // Simply check if the distance is less than or equal to the radius
    // Remove the buffer zone logic that might be causing confusion
    final bool newIsInside = distance <= _geofenceRadius;

    // Log detailed information for debugging
    developer.log(
      "GEOFENCE STATUS: Distance=${distance.toStringAsFixed(2)}m, Radius=${_geofenceRadius}m, Inside=$newIsInside",
    );
    developer.log(
      "LOCATION: Vehicle(${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}), Center(${_geofenceCenter.latitude.toStringAsFixed(6)}, ${_geofenceCenter.longitude.toStringAsFixed(6)})",
    );

    // Update state if there's a change
    if (_isInsideGeofence != newIsInside) {
      setState(() {
        _isInsideGeofence = newIsInside;
        _geofenceAlertShown = false; // Reset alert flag on state change
      });

      // Show notification if the vehicle crossed the boundary
      if (!newIsInside && !_geofenceAlertShown) {
        _showGeofenceAlert();
        _sendGeofenceNotification(newIsInside);
      } else if (newIsInside && !_geofenceAlertShown) {
        _sendGeofenceNotification(newIsInside);
      }
    }
  }

  // Show an alert when the vehicle leaves the geofence
  void _showGeofenceAlert() {
    setState(() {
      _geofenceAlertShown = true;
    });

    if (!mounted) return;

    // Calculate distance from geofence center
    final double distance = _calculateDistance(
      _geofenceCenter,
      _serverLocation,
    );
    final double overage = distance - _geofenceRadius;

    // Send theft detection data to server
    _sendTheftDetectionToServer();

    // Create alert title and message
    final String title = '⚠️ THEFT ALERT: Vehicle Left Geofence ⚠️';
    final String message =
        'Your vehicle has left the monitored area! It is ${overage.toStringAsFixed(1)}m beyond the boundary. Please check your vehicle immediately.';

    // Add to notifications and show popup alert
    NotificationService.showPopupNotification(context, title, message);

    // Also show a snackbar for immediate attention
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'ALERT: Vehicle has left the geofence area! (${overage.toStringAsFixed(1)}m beyond boundary)',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'VIEW DETAILS',
          textColor: Colors.white,
          onPressed: () {
            // Navigate to notification screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  // Send theft detection data to server when vehicle leaves geofence
  Future<void> _sendTheftDetectionToServer() async {
    if (!_isLocationReady || !mounted) return;

    try {
      // Create API URL for theft detection
      final url = Uri.parse('http://20.55.49.93:8000/api/theft-alert/');

      // Get vehicle data to send
      final data = {
        'license_plate': _licensePlate,
        'theft': true, // Mark this as theft detection
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

  // Send a notification when geofence state changes
  Future<void> _sendGeofenceNotification(bool isInside) async {
    try {
      // Calculate distance info for notification
      final double distance = _calculateDistance(
        _geofenceCenter,
        _serverLocation,
      );
      String distanceInfo = '';

      if (!isInside) {
        final double overage = distance - _geofenceRadius;
        distanceInfo = ' (${overage.toStringAsFixed(1)}m beyond boundary)';
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'geofence_channel',
            'Geofence Alerts',
            channelDescription:
                'Alerts when vehicle crosses geofence boundaries',
            importance: Importance.high,
            priority: Priority.high,
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final String title =
          isInside
              ? 'Vehicle Entered Geofence'
              : '⚠️ THEFT ALERT: Vehicle Left Geofence ⚠️';

      final String body =
          isInside
              ? 'Your vehicle has returned to the monitored area.'
              : 'Your vehicle has left the monitored area!$distanceInfo Please check your vehicle immediately.';

      // Add to notification screen
      NotificationService.addNotification(title: title, message: body);

      // Show system notification
      await _flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        platformDetails,
      );

      // Here you would add code to send an email notification
      // This would typically be done through a server API or Firebase Cloud Functions
      if (!isInside) {
        _sendGeofenceEmail();
      }
    } catch (e) {
      developer.log("Failed to send notification: $e");
      // Show a fallback in-app notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isInside
                ? 'Vehicle has entered the geofence area'
                : 'Vehicle has left the geofence area',
          ),
          backgroundColor: isInside ? Colors.green : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Send email notification (placeholder - would be implemented through backend)
  void _sendGeofenceEmail() {
    // This would typically call a backend API that handles sending emails
    developer.log("Email notification would be sent here");
    // Example implementation might use a cloud function or server endpoint:
    // http.post('your-api-endpoint.com/send-alert',
    //   body: {
    //     'alert': 'Vehicle left geofence',
    //     'location': '${_serverLocation.latitude},${_serverLocation.longitude}',
    //     'time': DateTime.now().toString()
    //   }
    // );
  }

  // Set up a new geofence
  void _setupGeofence() {
    // Try to parse the radius input
    double radius;
    try {
      radius = double.parse(_radiusController.text);
      // Add validation for minimum and maximum radius
      if (radius <= 0) {
        _showError('Radius must be greater than 0');
        return;
      }
      if (radius < 10) {
        _showError('Minimum radius is 10 meters');
        return;
      }
      if (radius > 100000) {
        _showError('Maximum radius is 100000 meters (100 km)');
        return;
      }
    } catch (e) {
      _showError('Please enter a valid number for radius');
      return;
    }

    // Get the current vehicle location from AWS Django server
    // IMPORTANT: This location will be used as the fixed center of the geofence
    // and will NOT move even as new server data comes in
    final LatLng locationToUse =
        _isLocationReady ? _serverLocation : _mapController.camera.center;

    // Set the geofence center and store original coordinates for reference
    // This center point will remain FIXED until the geofence is removed
    setState(() {
      _geofenceCenter = locationToUse;
      _geofenceRadius = radius;
      _isGeofenceActive = true;
      _isInsideGeofence = true; // Assume we're inside when setting up
      _geofenceAlertShown = false; // Reset alert status
    });

    // Save the geofence settings
    _saveGeofenceSettings();

    // Display locked coordinates
    final String latStr = locationToUse.latitude.toStringAsFixed(6);
    final String lngStr = locationToUse.longitude.toStringAsFixed(6);

    // Show confirmation with coordinates to emphasize the lock
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Geofence LOCKED at coordinates ($latStr, $lngStr) with radius of ${radius.toStringAsFixed(0)} meters',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );

    // Force an immediate geofence check
    _checkGeofence(_serverLocation);
  }

  // Remove the current geofence
  void _removeGeofence() {
    setState(() {
      _isGeofenceActive = false;
    });

    // Save settings
    _saveGeofenceSettings();

    // Center the map on the current vehicle location
    if (_isLocationReady && _mapReady) {
      // Move the map to the current server location
      _mapController.move(_serverLocation, 15.0);

      // Update the geofence center to match the current vehicle location
      // This will be used as the default if the user creates a new geofence
      setState(() {
        _geofenceCenter = _serverLocation;
      });
    }

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Geofence has been removed. Map centered on current vehicle location.',
        ),
      ),
    );
  }

  // Show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Geofencing${_licensePlate.isNotEmpty ? ' - $_licensePlate' : ''}',
        ),
        actions: [
          if (_accidentStatus) const Icon(Icons.warning, color: Colors.red),
          if (_isGeofenceActive)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _removeGeofence,
              tooltip: 'Remove Geofence',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status information
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isGeofenceActive
                          ? Icons.lock_outline
                          : Icons.circle_outlined,
                      color: _isGeofenceActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isGeofenceActive ? 'Geofence Locked' : 'No Geofence Set',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_isGeofenceActive && _isLocationReady)
                      IconButton(
                        icon: const Icon(Icons.crop_free, color: Colors.purple),
                        tooltip: 'Show both vehicle and geofence in view',
                        onPressed: () {
                          // Calculate center point between vehicle and geofence center
                          final double lat =
                              (_serverLocation.latitude +
                                  _geofenceCenter.latitude) /
                              2;
                          final double lng =
                              (_serverLocation.longitude +
                                  _geofenceCenter.longitude) /
                              2;

                          // Calculate distance to determine appropriate zoom
                          final double distance = _calculateDistance(
                            _geofenceCenter,
                            _serverLocation,
                          );

                          // Adjust zoom based on distance: closer = more zoom
                          double zoom = 15.0;
                          if (distance < 50) {
                            zoom = 17.0;
                          } else if (distance < 200) {
                            zoom = 16.0;
                          } else if (distance < 1000) {
                            zoom = 14.0;
                          } else if (distance < 5000) {
                            zoom = 12.0;
                          } else {
                            zoom = 10.0;
                          }

                          // Move to center point with calculated zoom
                          _mapController.move(LatLng(lat, lng), zoom);

                          // Force redraw
                          setState(() {});
                        },
                      ),
                    if (_isGeofenceActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              _isInsideGeofence
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isInsideGeofence
                                  ? Icons.check_circle_outline
                                  : Icons.warning,
                              color:
                                  _isInsideGeofence ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isInsideGeofence ? 'Inside' : 'Outside',
                              style: TextStyle(
                                color:
                                    _isInsideGeofence
                                        ? Colors.green
                                        : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                if (_isGeofenceActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Distance from center: ',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              _isLocationReady
                                  ? '${_calculateDistance(_geofenceCenter, _serverLocation).toStringAsFixed(1)} meters'
                                  : 'Unknown',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    _isInsideGeofence
                                        ? Colors.green
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'Geofence radius: ',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${_geofenceRadius.toStringAsFixed(1)} meters',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (_isLocationReady)
                          Text(
                            _calculateDistance(
                                      _geofenceCenter,
                                      _serverLocation,
                                    ) <=
                                    _geofenceRadius
                                ? 'Status: Inside boundary'
                                : 'Status: Outside boundary',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  _calculateDistance(
                                            _geofenceCenter,
                                            _serverLocation,
                                          ) <=
                                          _geofenceRadius
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_isGeofenceActive)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Note: Geofence is fixed at its original location and will not move with the vehicle',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                if (_lastUpdate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Last update: ${_lastUpdate!.hour}:${_lastUpdate!.minute.toString().padLeft(2, '0')}:${_lastUpdate!.second.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),

          // Map takes remaining space
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _isLocationReady
                            ? _serverLocation
                            : const LatLng(37.7749, -122.4194),
                    initialZoom: 15.0,
                    onMapReady: () {
                      setState(() {
                        _mapReady = true;
                      });

                      // If we already have a server location, center the map on it
                      if (_isLocationReady) {
                        _mapController.move(_serverLocation, 15.0);
                      }
                    },
                    interactionOptions: const InteractionOptions(
                      enableMultiFingerGestureRace: true,
                      flags: InteractiveFlag.all,
                    ),
                    onTap: (tapPosition, latLng) {
                      // Update geofence center position if long-pressed
                      if (_isGeofenceActive) {
                        setState(() {
                          _geofenceCenter = latLng;
                        });
                        _saveGeofenceSettings();
                      }
                    },
                    // Add this handler to ensure accurate display when zooming
                    onPositionChanged: (MapCamera position, bool hasGesture) {
                      if (hasGesture) {
                        // Force a redraw when user zooms or pans
                        setState(() {
                          // This empty setState forces the map to redraw all layers
                        });
                      }
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
                    ),
                    // Draw geofence circle if active
                    if (_isGeofenceActive)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _geofenceCenter,
                            radius: _geofenceRadius,
                            useRadiusInMeter:
                                true, // Ensure radius is in meters
                            color: Colors.blue.withOpacity(0.2),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 2.0,
                          ),
                        ],
                      ),
                    // Marker for geofence center
                    if (_isGeofenceActive)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _geofenceCenter,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.lock_outline,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    // Marker for vehicle location
                    if (_isLocationReady)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _serverLocation,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.red,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // Overlay for radius input
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white.withOpacity(0.9),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Geofence Radius (meters): '),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _radiusController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(),
                                  hintText: '10-100000 meters',
                                  hintStyle: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Note: Map zoom level does not affect geofence radius',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                if (_mapReady && _isLocationReady) {
                                  _mapController.move(_serverLocation, 15.0);
                                }
                              },
                              icon: const Icon(Icons.my_location),
                              label: const Text('Go to Vehicle'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _setupGeofence,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text(
                                _isGeofenceActive
                                    ? 'Update Geofence'
                                    : 'Set Geofence at Vehicle',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Loading indicator
                if (!_isLocationReady)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Fetching vehicle location...'),
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            mini: true,
            onPressed: () {
              if (_mapReady) {
                final currentZoom = _mapController.camera.zoom;
                _mapController.move(
                  _mapController.camera.center,
                  currentZoom + 0.5,
                );
                // Force a redraw after zoom
                setState(() {});
              }
            },
            tooltip: 'Zoom in (does not change geofence radius)',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            mini: true,
            onPressed: () {
              if (_mapReady) {
                final currentZoom = _mapController.camera.zoom;
                _mapController.move(
                  _mapController.camera.center,
                  currentZoom - 0.5,
                );
                // Force a redraw after zoom
                setState(() {});
              }
            },
            tooltip: 'Zoom out (does not change geofence radius)',
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}
