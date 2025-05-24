import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'geofencing_screen.dart';
import 'notification_screen.dart';
import 'server_service.dart';
import 'django_tracking_screen.dart';
import 'user_profile_screen.dart';
import 'auth/login_screen.dart';
import 'utils/shared_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize notifications
  await NotificationService.initializeNotifications();

  // Request notification permissions explicitly
  await NotificationService.requestNotificationPermissions();

  // Check login status
  bool isLoggedIn = await SharedPrefs.isLoggedIn();

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vehicle Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Add modern theme settings
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
      ),
      home: isLoggedIn ? const MainScreen() : const LoginScreen(),
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
