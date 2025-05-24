import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'notification_screen.dart';

class TestConnectionScreen extends StatefulWidget {
  const TestConnectionScreen({super.key});

  @override
  State<TestConnectionScreen> createState() => _TestConnectionScreenState();
}

class _TestConnectionScreenState extends State<TestConnectionScreen> {
  bool isConnecting = false;
  bool isConnected = false;
  String error = '';
  String responseData = '';

  // Server connection settings
  final String serverUrl = 'http://20.55.49.93:8000/api/status/';

  // Test connection to the Django server
  Future<void> testServerConnection() async {
    setState(() {
      isConnecting = true;
      isConnected = false;
      error = '';
      responseData = '';
    });

    try {
      developer.log('Testing connection to: $serverUrl');

      // Use GET request instead of POST - this matches what the server expects
      final response = await http
          .get(Uri.parse(serverUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Connection successful
        final data = json.decode(response.body);
        developer.log('Connected successfully! Response: $data');

        setState(() {
          isConnecting = false;
          isConnected = true;
          error = '';
          responseData = response.body;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to server successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Check for alert conditions in the response - only if explicitly true
        final bool alert = data.containsKey('alert') && data['alert'] == true;

        // Only show notification if alert is explicitly true
        if (alert) {
          developer.log('Alert condition detected in server response');

          // Extract location
          final String location =
              '${data['latitude'] ?? '0'}, ${data['longitude'] ?? '0'}';

          // Show notification
          NotificationService.handleAccidentNotification(
            context,
            true,
            location,
          );
        }

        // Check for theft detection in the response - only if explicitly true
        final bool theftDetection =
            data.containsKey('theft') && data['theft'] == true;

        // Only show notification if theft is explicitly true
        if (theftDetection) {
          developer.log('Theft detection condition in server response');

          // Extract location
          final String location =
              '${data['latitude'] ?? '0'}, ${data['longitude'] ?? '0'}';

          // Show notification
          NotificationService.handleTheftNotification(context, true, location);
        }
      } else {
        setState(() {
          isConnecting = false;
          isConnected = false;
          error = 'Server returned status code: ${response.statusCode}';
          if (response.body.isNotEmpty) {
            try {
              // Try to get more detailed error information from response
              final errorData = json.decode(response.body);
              error += ' - ${errorData['detail'] ?? 'Unknown error'}';
            } catch (e) {
              // If response body can't be parsed, just show the body
              if (response.body.length < 100) {
                error += ' - ${response.body}';
              }
            }
          }
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${response.statusCode}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      developer.log('Connection error: $e');
      setState(() {
        isConnecting = false;
        isConnected = false;
        error = e.toString();
      });

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Django Connection Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Server Connection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: ${isConnected ? "Connected" : "Disconnected"}'),
            Text('Server URL: $serverUrl'),

            // Connection test button
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isConnecting ? null : testServerConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child:
                    isConnecting
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 3,
                          ),
                        )
                        : const Text(
                          'TEST CONNECTION',
                          style: TextStyle(fontSize: 16),
                        ),
              ),
            ),

            // Error display
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Error:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text(error, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),

            // Response data display
            if (responseData.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Server Response:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(json.decode(responseData)),
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
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
