import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

class ServerService {
  // Singleton pattern
  static final ServerService _instance = ServerService._internal();
  factory ServerService() => _instance;
  ServerService._internal();

  // Server connection details - updated to use the simplified API
  static const String serverUrl = 'http://20.55.49.93:8000/api/status/';

  // API method
  static const String apiMethod = 'GET'; // Changed from POST to GET

  // Data polling timer
  Timer? _dataPollingTimer;

  // Status flags
  bool _isConnected = false;

  // Alert state tracking
  bool _previousAlertState = false;
  bool _previousTheftState = false;
  DateTime? _lastAlertTime;
  static const Duration _minimumAlertInterval = Duration(seconds: 30);

  // Stream controllers for various events
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _locationDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _alertController = StreamController<Map<String, dynamic>>.broadcast();
  final _theftDetectionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Stream getters
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get locationData =>
      _locationDataController.stream;
  Stream<Map<String, dynamic>> get alertEvents => _alertController.stream;
  Stream<Map<String, dynamic>> get theftEvents =>
      _theftDetectionController.stream;

  // Getter for connection status
  bool get isConnected => _isConnected;

  // Initialize the service and start polling
  void initialize(BuildContext context) {
    developer.log('Initializing server service...');

    // Start data polling from the server
    startPolling(context);
  }

  // Start polling data from the server
  void startPolling(BuildContext context) {
    // Cancel existing timer if any
    _dataPollingTimer?.cancel();

    // Initial fetch
    fetchServerData(context);

    // Set up timer for periodic updates (every 5 seconds)
    _dataPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchServerData(context);
    });

    developer.log('Started polling server data');
  }

  // Stop polling data
  void stopPolling() {
    _dataPollingTimer?.cancel();
    _dataPollingTimer = null;
    _isConnected = false;
    _connectionStatusController.add(false);
    developer.log('Stopped polling server data');
  }

  // Fetch data from server
  Future<void> fetchServerData(BuildContext context) async {
    try {
      // Use a single client for better connection handling
      final client = http.Client();
      try {
        http.Response response;

        if (apiMethod == 'POST') {
          // Use POST method with minimal required parameters
          final requestData = {'license_plate': 'APP123'};
          developer.log('Sending data to server: ${json.encode(requestData)}');

          response = await client
              .post(
                Uri.parse(serverUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'Connection': 'keep-alive',
                },
                body: json.encode(requestData),
              )
              .timeout(const Duration(seconds: 5));
        } else {
          // Use GET method by default
          developer.log('Getting data from server: $serverUrl');
          response = await client
              .get(Uri.parse(serverUrl), headers: {'Connection': 'keep-alive'})
              .timeout(const Duration(seconds: 5));
        }

        developer.log('Response status: ${response.statusCode}');
        developer.log('Response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Connection successful
          final wasConnected = _isConnected;
          _isConnected = true;

          // Notify connection status change if needed
          if (!wasConnected) {
            _connectionStatusController.add(true);
            developer.log('Connected to server successfully');

            // Show connection established notification
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Connected to server successfully'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }

          // Parse response data
          Map<String, dynamic> data;
          try {
            data = json.decode(response.body);
            developer.log('Successfully parsed response data: $data');
          } catch (e) {
            developer.log('Error parsing response: $e');
            data = {'error': 'Invalid response format'};
          }

          // Create vehicle data from response
          Map<String, dynamic> vehicleData = {
            'license_plate': data['license_plate'] ?? 'Unknown',
            'latitude': data['latitude'],
            'longitude': data['longitude'],
          };

          // Process theft status - only if explicitly true
          bool theft = false;
          if (data.containsKey('theft')) {
            theft = data['theft'] == true;
          }
          vehicleData['theft'] = theft;

          // Process alert (accident) status - only if explicitly true
          bool alert = false;
          if (data.containsKey('alert')) {
            alert = data['alert'] == true;
          }
          vehicleData['alert'] = alert;

          // Add timestamp if available
          if (data.containsKey('timestamp')) {
            vehicleData['timestamp'] = data['timestamp'];
          } else if (data.containsKey('last_updated')) {
            vehicleData['timestamp'] = data['last_updated'];
          }

          developer.log('Processed vehicle data: $vehicleData');

          // Broadcast the vehicle data to listeners
          _locationDataController.add(vehicleData);

          // Only trigger alerts if:
          // 1. There's a change from false to true AND
          // 2. Enough time has passed since the last alert
          final DateTime now = DateTime.now();
          if (alert &&
              !_previousAlertState &&
              (_lastAlertTime == null ||
                  now.difference(_lastAlertTime!) > _minimumAlertInterval)) {
            developer.log('NEW accident alert detected!');
            _alertController.add(vehicleData);
            _lastAlertTime = now;
          }
          _previousAlertState = alert;

          if (theft && !_previousTheftState) {
            developer.log('NEW theft alert detected!');
            _theftDetectionController.add(vehicleData);
          }
          _previousTheftState = theft;
        } else {
          // Failed to connect
          if (_isConnected) {
            _isConnected = false;
            _connectionStatusController.add(false);
            developer.log(
              'Connection to server lost. Status code: ${response.statusCode}, Response: ${response.body}',
            );

            // Show connection lost notification
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Connection lost. Server returned ${response.statusCode} - ${response.body}',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } finally {
        // Always close the client to prevent resource leaks
        client.close();
      }
    } catch (e) {
      // Error in connection
      if (_isConnected) {
        _isConnected = false;
        _connectionStatusController.add(false);
        developer.log('Failed to connect to server: $e');

        // Show connection error notification
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to connect to server: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    stopPolling();
    _connectionStatusController.close();
    _locationDataController.close();
    _alertController.close();
    _theftDetectionController.close();
  }
}
