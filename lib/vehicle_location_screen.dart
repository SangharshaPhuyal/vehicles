import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'utils/shared_prefs.dart';
import 'dart:developer' as developer;

class VehicleLocationScreen extends StatefulWidget {
  const VehicleLocationScreen({super.key});

  @override
  _VehicleLocationScreenState createState() => _VehicleLocationScreenState();
}

class _VehicleLocationScreenState extends State<VehicleLocationScreen>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic> _vehicleData = {};
  late Timer _refreshTimer;
  String _serverUrl = '';
  String _vehicleId = '';

  @override
  void initState() {
    super.initState();
    _loadServerSettings();
    // Set up a refresh timer to fetch data every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchVehicleData();
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // Keep state when switching tabs

  Future<void> _loadServerSettings() async {
    try {
      _serverUrl = await SharedPrefs.getServerUrl();
      _vehicleId = await SharedPrefs.getVehicleId();

      if (_vehicleId.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please set a vehicle ID in your profile';
        });
      } else {
        _fetchVehicleData();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading settings: $e';
      });
    }
  }

  Future<void> _fetchVehicleData() async {
    if (_vehicleId.isEmpty || _serverUrl.isEmpty) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final response = await http
          .get(
            Uri.parse('$_serverUrl/vehicles/$_vehicleId/'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _vehicleData = data;
          _isLoading = false;
        });
        developer.log('Fetched vehicle data: $data');
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Error: ${response.statusCode} ${response.reasonPhrase}';
        });
        developer.log(
          'Error fetching vehicle data: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection error: $e';
      });
      developer.log('Exception fetching vehicle data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Location')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage.isNotEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      style: const TextStyle(fontSize: 16, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _fetchVehicleData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _fetchVehicleData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vehicle info card
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.directions_car,
                                    size: 28,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _vehicleData['license_plate'] ?? _vehicleId,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              _buildInfoRow(
                                Icons.location_on,
                                'Current Location',
                                '${_vehicleData['latitude'] ?? 'N/A'}, ${_vehicleData['longitude'] ?? 'N/A'}',
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                Icons.speed,
                                'Speed',
                                '${_vehicleData['speed'] ?? 'N/A'} km/h',
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                Icons.access_time,
                                'Last Updated',
                                _vehicleData['timestamp'] != null
                                    ? DateTime.parse(
                                      _vehicleData['timestamp'],
                                    ).toString()
                                    : 'N/A',
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                _isAlertTrue()
                                    ? Icons.warning_amber
                                    : Icons.check_circle,
                                'Status',
                                _isAlertTrue()
                                    ? 'Alert! Vehicle may be stolen'
                                    : 'Normal',
                                color:
                                    _isAlertTrue() ? Colors.red : Colors.green,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Location history section
                      if (_vehicleData['history'] != null) ...[
                        const Text(
                          'Location History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: (_vehicleData['history'] as List).length,
                            separatorBuilder:
                                (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item =
                                  (_vehicleData['history'] as List)[index];
                              return ListTile(
                                title: Text(
                                  'Location: ${item['latitude']}, ${item['longitude']}',
                                ),
                                subtitle: Text(
                                  DateTime.parse(item['timestamp']).toString(),
                                ),
                                leading: const Icon(Icons.history),
                                trailing:
                                    _isAlertFromHistory(item)
                                        ? const Icon(
                                          Icons.warning_amber,
                                          color: Colors.red,
                                        )
                                        : null,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchVehicleData,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.blueGrey),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to properly check if alert is true
  bool _isAlertTrue() {
    // Handle various ways alert might be represented: boolean true, string "true", or number 1
    if (_vehicleData.containsKey('alert')) {
      var alert = _vehicleData['alert'];
      if (alert is bool) {
        return alert;
      } else if (alert is String) {
        return alert.toLowerCase() == 'true';
      } else if (alert is num) {
        return alert > 0;
      }
    }
    return false;
  }

  // Helper method to check alert from history
  bool _isAlertFromHistory(dynamic item) {
    if (item.containsKey('alert')) {
      var alert = item['alert'];
      if (alert is bool) {
        return alert;
      } else if (alert is String) {
        return alert.toLowerCase() == 'true';
      } else if (alert is num) {
        return alert > 0;
      }
    }
    return false;
  }
}
