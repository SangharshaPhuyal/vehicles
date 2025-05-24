import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'notification_screen.dart';

class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({super.key});

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  // This will store our current location
  LocationData? _currentLocation;
  // This will help us get location
  final Location _location = Location();
  // This controls our map
  bool _mapReady = false;
  final MapController _mapController = MapController();
  // Default location (for emulators)
  final LatLng _defaultLocation = const LatLng(37.7749, -122.4194);
  // Error tracking
  bool _hadLocationError = false;
  bool _hasInternetConnection = true;
  // Add tracking toggle
  bool _isTracking = true;
  // AWS Django server settings
  final String _serverUrl = 'http://20.55.49.93:8000/api/status/';
  Timer? _serverTimer;
  bool _useServerData = true;
  LatLng _serverLocation = const LatLng(0, 0);
  String _serverError = '';
  final bool _accidentStatus = false;
  final String _licensePlate = '';
  final String _lastUpdateTime = '';
  // Track previous alert state to avoid duplicate notifications
  bool _previousAlertState = false;

  @override
  void initState() {
    super.initState();
    // Check internet connection first
    _checkInternetConnection();
    // When app starts, get location
    _getCurrentLocation();
    // Start server polling
    _startServerPolling();
  }

  @override
  void dispose() {
    _serverTimer?.cancel();
    super.dispose();
  }

  // Start periodic server data polling
  void _startServerPolling() {
    // Fetch initially
    _fetchServerData();

    // Then set up timer for periodic updates
    _serverTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchServerData();
    });
  }

  // Fetch location data from AWS Django server
  Future<void> _fetchServerData() async {
    if (!_hasInternetConnection) {
      developer.log("Skipping server update due to no internet connection");
      return;
    }

    try {
      developer.log("Attempting to connect to server: $_serverUrl");

      // Using a persistent client to prevent broken pipe errors
      final client = http.Client();
      try {
        final response = await client
            .get(Uri.parse(_serverUrl), headers: {'Connection': 'keep-alive'})
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                // On timeout, close client properly
                client.close();
                throw TimeoutException('Server connection timed out');
              },
            );

        developer.log("Server response status: ${response.statusCode}");
        developer.log("Server response body: ${response.body}");

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          developer.log("Parsed server data: $data");

          // Check if the required fields exist in the response
          if (data['latitude'] != null && data['longitude'] != null) {
            try {
              double lat = double.parse(data['latitude'].toString());
              double lng = double.parse(data['longitude'].toString());

              // Only consider alert true if explicitly set to true
              bool alert = false;
              if (data.containsKey('alert')) {
                alert = data['alert'] == true;
              }

              String licensePlate = data['license_plate'] ?? 'Unknown';
              String timeStr = data['timestamp'] ?? data['last_updated'] ?? '';

              developer.log(
                "Server location parsed: lat=$lat, lng=$lng, alert=$alert, plate=$licensePlate, time=$timeStr",
              );

              if (mounted) {
                setState(() {
                  _serverLocation = LatLng(lat, lng);
                  _serverError = '';

                  // If using server data and tracking is on, update map position
                  if (_useServerData && _isTracking && _mapReady) {
                    _mapController.move(
                      _serverLocation,
                      _mapController.camera.zoom,
                    );
                  }

                  // Only show notification if alert is explicitly true AND it's a new alert
                  // Store previous alert state to compare
                  if (alert && !_previousAlertState) {
                    NotificationService.showPopupNotification(
                      context,
                      '⚠️ ALERT ⚠️',
                      'Vehicle $licensePlate has reported an alert! Please check immediately.',
                    );
                  }
                  _previousAlertState = alert;
                });
              }

              developer.log(
                "Server update successful: lat=$lat, lng=$lng, alert=$alert, plate=$licensePlate, time=$timeStr",
              );
            } catch (e) {
              developer.log("Error parsing server data: $e");
              if (mounted) {
                setState(() {
                  _serverError = 'Error parsing data: $e';
                });
              }
            }
          } else {
            developer.log("Server update missing location fields");
            if (mounted) {
              setState(() {
                _serverError = 'No location data available';
              });
            }
          }
        } else {
          developer.log("Server request failed: ${response.statusCode}");
          if (mounted) {
            setState(() {
              _serverError = 'Request failed: ${response.statusCode}';
            });
          }
        }
      } finally {
        // Always properly close the client to avoid broken pipes
        client.close();
      }
    } catch (e) {
      developer.log("Server request error: $e");
      if (mounted) {
        setState(() {
          _serverError = 'Connection error: $e';
        });
      }
    }
  }

  // Check for internet connectivity
  Future<void> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        setState(() {
          _hasInternetConnection = true;
        });
      }
    } on SocketException catch (_) {
      setState(() {
        _hasInternetConnection = false;
      });
      developer.log("No internet connection available");

      // Show a message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No internet connection. Maps may not load properly.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Helper method to safely convert location data to LatLng
  LatLng _safeLocationToLatLng(LocationData? locationData) {
    if (locationData == null) {
      developer.log("Location data is null, using default location");
      return _defaultLocation;
    }

    try {
      // Extract values and explicitly handle all possible cases
      dynamic latValue = locationData.latitude;
      dynamic lngValue = locationData.longitude;

      // Debug printouts
      developer.log(
        "Location type check - lat: ${latValue.runtimeType}, lng: ${lngValue.runtimeType}",
      );

      if (latValue == null || lngValue == null) {
        developer.log("Latitude or longitude is null, using default location");
        return _defaultLocation;
      }

      double lat;
      double lng;

      // Handle different possible types for latitude
      if (latValue is double) {
        lat = latValue;
      } else if (latValue is int) {
        lat = latValue.toDouble();
      } else {
        // Try parsing as a last resort
        try {
          lat = double.parse(latValue.toString());
        } catch (e) {
          developer.log("Could not parse latitude: $latValue, using default");
          return _defaultLocation;
        }
      }

      // Handle different possible types for longitude
      if (lngValue is double) {
        lng = lngValue;
      } else if (lngValue is int) {
        lng = lngValue.toDouble();
      } else {
        // Try parsing as a last resort
        try {
          lng = double.parse(lngValue.toString());
        } catch (e) {
          developer.log("Could not parse longitude: $lngValue, using default");
          return _defaultLocation;
        }
      }

      developer.log("Successfully converted location: lat=$lat, lng=$lng");
      return LatLng(lat, lng);
    } catch (e) {
      developer.log("Error converting location data: $e");
      _hadLocationError = true;
      return _defaultLocation;
    }
  }

  // This function gets our current location
  Future<void> _getCurrentLocation() async {
    try {
      developer.log("Starting location fetch process");
      // First ask for permission
      bool serviceEnabled;
      PermissionStatus permissionGranted;

      try {
        serviceEnabled = await _location.serviceEnabled();
        if (!serviceEnabled) {
          serviceEnabled = await _location.requestService();
          if (!serviceEnabled) {
            // Show a message to the user that location services are not enabled
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Location services are disabled. Please enable them.',
                  ),
                ),
              );
            }
            // Use default location instead of returning
            _useDefaultLocation("Location services disabled");
            return;
          }
        }
      } catch (e) {
        developer.log("Error checking location service: $e");
        // For emulators, we might need to bypass this check
        _useDefaultLocation("Location service error: $e");
        return;
      }

      try {
        permissionGranted = await _location.hasPermission();
        if (permissionGranted == PermissionStatus.denied) {
          permissionGranted = await _location.requestPermission();
          if (permissionGranted != PermissionStatus.granted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Location permission denied. Please grant it in settings.',
                  ),
                ),
              );
            }
            // Use default location instead of returning
            _useDefaultLocation("Location permission denied");
            return;
          }
        }
      } catch (e) {
        developer.log("Error checking location permission: $e");
        // For emulators, we might need different handling
        _useDefaultLocation("Location permission error: $e");
        return;
      }

      // Get location one time
      try {
        _currentLocation = await _location.getLocation();
        developer.log("Got initial location: $_currentLocation");

        // For emulators, you might want to use a default location if real one fails
        if (_currentLocation == null ||
            _currentLocation!.latitude == null ||
            _currentLocation!.longitude == null) {
          // Default to a location
          _useDefaultLocation("Couldn't get real location");
          return;
        }

        // Test converting to ensure it works
        try {
          _safeLocationToLatLng(_currentLocation);
        } catch (e) {
          developer.log("Location conversion test failed: $e");
          _useDefaultLocation("Location conversion test failed");
          return;
        }

        if (mounted) {
          setState(() {});
        }

        // Configure location for accurate tracking
        _location.changeSettings(
          accuracy: LocationAccuracy.high,
          interval: 5000, // Update every 5 seconds
          distanceFilter: 5, // Update if moved 5 meters
        );

        // Listen to location changes
        _location.onLocationChanged.listen((LocationData currentLocation) {
          if (mounted) {
            setState(() {
              try {
                _currentLocation = currentLocation;

                // Test conversion before using
                final latLng = _safeLocationToLatLng(currentLocation);

                // Move map to new location if location is valid, tracking is active, and not using server data
                if (_mapReady && _isTracking && !_useServerData) {
                  try {
                    _mapController.move(
                      latLng,
                      _mapController.camera.zoom,
                    ); // Maintain zoom level
                  } catch (e) {
                    developer.log("Error moving map: $e");
                  }
                }
              } catch (e) {
                developer.log("Error handling location update: $e");
              }
            });
          }
        });
      } catch (e) {
        developer.log("Error getting location: $e");
        // If we can't get location, use a default
        _useDefaultLocation("Error getting location: $e");
      }
    } catch (e) {
      developer.log("General error in _getCurrentLocation: $e");
      // Show an error message to the user
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
      _useDefaultLocation("General error: $e");
    }
  }

  void _useDefaultLocation(String reason) {
    developer.log("Using default location. Reason: $reason");
    _hadLocationError = true;

    // Create a "safe" LocationData object with explicit doubles
    _currentLocation = LocationData.fromMap({
      "latitude": _defaultLocation.latitude,
      "longitude": _defaultLocation.longitude,
      "accuracy": 0.0,
      "altitude": 0.0,
      "speed": 0.0,
      "speed_accuracy": 0.0,
      "heading": 0.0,
      "time": DateTime.now().millisecondsSinceEpoch.toDouble(),
      "isMock": true,
    });

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create LatLng from location data, with fallback
    LatLng currentPosition;

    try {
      // Use either server location or device location based on toggle
      if (_useServerData) {
        currentPosition = _serverLocation;
      } else {
        currentPosition = _safeLocationToLatLng(_currentLocation);
      }
    } catch (e) {
      developer.log("Error in build method location conversion: $e");
      currentPosition = _defaultLocation;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _useServerData
              ? 'Vehicle Location${_licensePlate.isNotEmpty ? ' - $_licensePlate' : ''}'
              : (_hadLocationError
                  ? 'Using Default Location'
                  : 'My Live Location'),
        ),
        actions: [
          // Add server data toggle
          IconButton(
            icon: Icon(
              _useServerData ? Icons.cloud_done : Icons.cloud_off,
              color: _useServerData ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _useServerData = !_useServerData;

                // If switching to server data, update map position
                if (_useServerData && _mapReady) {
                  _mapController.move(
                    _serverLocation,
                    _mapController.camera.zoom,
                  );
                } else if (!_useServerData &&
                    _mapReady &&
                    _currentLocation != null) {
                  // If switching to device location, update map position
                  final latLng = _safeLocationToLatLng(_currentLocation);
                  _mapController.move(latLng, _mapController.camera.zoom);
                }
              });
            },
            tooltip:
                _useServerData ? 'Using Server Data' : 'Using Device Location',
          ),
          // Add accident status indicator
          if (_accidentStatus) const Icon(Icons.warning, color: Colors.red),
          // Add internet status indicator
          if (!_hasInternetConnection)
            const Icon(Icons.signal_wifi_off, color: Colors.red),
          // Add tracking toggle
          IconButton(
            icon: Icon(
              _isTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: _isTracking ? Colors.blue : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _isTracking = !_isTracking;
                if (_isTracking && _mapReady) {
                  try {
                    if (_useServerData) {
                      _mapController.move(
                        _serverLocation,
                        _mapController.camera.zoom,
                      );
                    } else if (_currentLocation != null) {
                      final latLng = _safeLocationToLatLng(_currentLocation);
                      _mapController.move(latLng, _mapController.camera.zoom);
                    }
                  } catch (e) {
                    developer.log("Error centering map: $e");
                  }
                }
              });
            },
            tooltip: _isTracking ? 'Tracking On' : 'Tracking Off',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_mapReady) {
                try {
                  LatLng latLng;
                  if (_useServerData) {
                    latLng = _serverLocation;
                  } else {
                    try {
                      latLng = _safeLocationToLatLng(_currentLocation);
                    } catch (e) {
                      developer.log("Error getting location for centering: $e");
                      latLng = _defaultLocation;
                    }
                  }

                  _mapController.move(latLng, 15.0);
                } catch (e) {
                  developer.log("Error centering map: $e");
                }
              }
            },
          ),
        ],
      ),
      body:
          (_currentLocation == null && !_useServerData)
              ? const Center(child: CircularProgressIndicator())
              : !_hasInternetConnection
              ? Stack(
                children: [
                  // Show a simple placeholder map when there's no internet
                  Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 100,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Map unavailable without internet',
                            style: TextStyle(fontSize: 18),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Check your connection and try again',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Still show your current location on the placeholder
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.my_location, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Lat: ${currentPosition.latitude.toStringAsFixed(4)}\nLng: ${currentPosition.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
              : Column(
                children: [
                  if (_serverError.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.red.shade50,
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _serverError,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_lastUpdateTime.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.shade50,
                      child: Row(
                        children: [
                          const Icon(Icons.update, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Last update: $_lastUpdateTime',
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  // Map takes remaining space
                  Expanded(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: currentPosition,
                        initialZoom: 15.0,
                        onMapReady: () {
                          setState(() {
                            _mapReady = true;
                          });
                        },
                        // Enable interactions
                        interactionOptions: const InteractionOptions(
                          enableMultiFingerGestureRace: true,
                          flags: InteractiveFlag.all,
                        ),
                        // Allow full zoom range for more control
                        minZoom: 1.0,
                        maxZoom: 19.0,
                        // Don't auto-move the map during updates (handled by tracking toggle)
                        keepAlive: true,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.app',
                          // Add fallback URL
                          fallbackUrl:
                              'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                          // Add additional servers
                          subdomains: const ['a', 'b', 'c'],
                          // Add required attribution
                          additionalOptions: {
                            'attribution': '© OpenStreetMap contributors',
                          },
                          // Handle errors
                          errorImage: const NetworkImage(
                            'https://cdn.jsdelivr.net/gh/flutter_map/flutter_map@master/tile_error_image.png',
                          ),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: currentPosition,
                              width: 80,
                              height: 80,
                              child: Column(
                                children: [
                                  _useServerData
                                      ? const Icon(
                                        Icons.directions_car,
                                        color: Colors.blue,
                                        size: 40,
                                        shadows: [
                                          Shadow(
                                            offset: Offset(1, 1),
                                            blurRadius: 3.0,
                                            color: Colors.black38,
                                          ),
                                        ],
                                      )
                                      : Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                  // Show data source indicator
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color:
                                            _useServerData
                                                ? Colors.blue
                                                : (_hadLocationError
                                                    ? Colors.red
                                                    : Colors.green),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      _useServerData
                                          ? "SERVER"
                                          : (_hadLocationError
                                              ? "DEFAULT"
                                              : "DEVICE"),
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            _useServerData
                                                ? Colors.blue
                                                : (_hadLocationError
                                                    ? Colors.red
                                                    : Colors.green),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                // Allow more precise zoom-in
                _mapController.move(
                  _mapController.camera.center,
                  currentZoom + 0.5,
                );
              }
            },
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            mini: true,
            onPressed: () {
              if (_mapReady) {
                final currentZoom = _mapController.camera.zoom;
                // Allow more precise zoom-out
                _mapController.move(
                  _mapController.camera.center,
                  currentZoom - 0.5,
                );
              }
            },
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              // Check internet before refreshing
              _checkInternetConnection();
              if (_useServerData) {
                _fetchServerData();
              } else {
                _getCurrentLocation();
              }
            },
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
