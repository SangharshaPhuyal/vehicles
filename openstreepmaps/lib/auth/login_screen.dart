import 'package:flutter/material.dart';
import 'signup_screen.dart';
import '../utils/auth_service.dart';
import '../utils/shared_prefs.dart';
import '../main.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Get the server URL - use default if not set
      final serverUrl = await SharedPrefs.getServerUrl();

      // Attempt to login with the Django server
      final response = await http
          .post(
            Uri.parse('$serverUrl/auth/login/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': _emailController.text,
              'password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Parse response
        final data = json.decode(response.body);

        // Save login state and user data
        await SharedPrefs.setLoggedIn(true);
        await SharedPrefs.setEmail(_emailController.text);

        // Save user name if provided
        if (data.containsKey('name') && data['name'] != null) {
          await SharedPrefs.setName(data['name']);
        }

        // Save vehicle ID if provided
        if (data.containsKey('vehicle_id') && data['vehicle_id'] != null) {
          await SharedPrefs.setVehicleId(data['vehicle_id']);
        }

        if (mounted) {
          // Navigate to main screen and remove all previous routes
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
      } else {
        // For development fallback to mock service if server fails
        final success = await AuthService.login(
          _emailController.text,
          _passwordController.text,
        );

        if (success) {
          // Save login state
          await SharedPrefs.setLoggedIn(true);
          await SharedPrefs.setEmail(_emailController.text);

          if (mounted) {
            // Navigate to main screen and remove all previous routes
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage = 'Invalid email or password';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // For development, try mock auth if server connection fails
      try {
        final success = await AuthService.login(
          _emailController.text,
          _passwordController.text,
        );

        if (success) {
          // Save login state
          await SharedPrefs.setLoggedIn(true);
          await SharedPrefs.setEmail(_emailController.text);

          if (mounted) {
            // Navigate to main screen and remove all previous routes
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainScreen()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _errorMessage = 'Invalid email or password';
            _isLoading = false;
          });
        }
      } catch (_) {
        setState(() {
          _errorMessage = 'An error occurred. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App logo or icon
                  const Icon(
                    Icons.directions_car_filled,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Vehicle Tracker',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Subtitle
                  const Text(
                    'Sign in to your account',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Error message if any
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red[700]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_errorMessage.isNotEmpty) const SizedBox(height: 24),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Login button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Text(
                              'LOG IN',
                              style: TextStyle(fontSize: 16),
                            ),
                  ),
                  const SizedBox(height: 24),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(color: Colors.grey),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignupScreen(),
                            ),
                          );
                        },
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
