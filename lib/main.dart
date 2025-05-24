import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'geofencing_screen.dart';
import 'notification_screen.dart';
import 'server_service.dart';
import 'django_tracking_screen.dart';
import 'user_profile_screen.dart';
import 'auth/login_screen.dart';
import 'utils/shared_prefs.dart';
import 'package:shared_preferences.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenStreetMap',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthenticationWrapper(),
    );
  }
}

class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  _AuthenticationWrapperState createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  late Future<bool> _isLoggedInFuture;

  @override
  void initState() {
    super.initState();
    _isLoggedInFuture = _checkLoginStatus();
  }

  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final authService = AuthService(prefs);
    return authService.isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data == true) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final ServerService _serverService = ServerService();

  @override
  void initState() {
    super.initState();
    _initializeServerConnection();
  }

  Future<void> _initializeServerConnection() async {
    // Always connect to the server
    _serverService.initialize(context);
  }

  @override
  void dispose() {
    // Clean up server service
    _serverService.dispose();
    super.dispose();
  }

  // List of screens to navigate between
  final List<Widget> _screens = [
    const DjangoTrackingScreen(),
    const GeofencingScreen(),
    const NotificationScreen(),
    const UserProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Vehicle',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.circle_outlined),
            label: 'Geofence',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
        showUnselectedLabels: true,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
