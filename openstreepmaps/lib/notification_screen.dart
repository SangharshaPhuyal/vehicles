import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Notification item model
class NotificationItem {
  String title;
  String message;
  DateTime timestamp;
  bool isRead;
  String
  type; // Add type field to distinguish between different notification types

  NotificationItem({
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.type = 'general', // Default type is 'general'
  });
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? notificationStrings = prefs.getStringList(
        'notifications',
      );

      setState(() {
        if (notificationStrings != null) {
          _notifications =
              notificationStrings.map((str) {
                final parts = str.split('|');
                if (parts.length >= 3) {
                  return NotificationItem(
                    title: parts[0],
                    message: parts[1],
                    timestamp: DateTime.parse(parts[2]),
                    isRead: parts.length > 3 ? parts[3] == 'true' : false,
                    type: parts.length > 4 ? parts[4] : 'general',
                  );
                }
                return NotificationItem(
                  title: 'Notification',
                  message: str,
                  timestamp: DateTime.now(),
                  isRead: false,
                  type: 'general',
                );
              }).toList();

          // Sort notifications by timestamp (newest first)
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
        _isLoading = false;
      });
    } catch (e) {
      developer.log("Error loading notifications: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      for (var notification in _notifications) {
        notification.isRead = true;
      }
    });

    try {
      await _saveNotifications();
    } catch (e) {
      developer.log("Error saving notifications: $e");
    }
  }

  Future<void> _clearAllNotifications() async {
    setState(() {
      _notifications.clear();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notifications');
    } catch (e) {
      developer.log("Error clearing notifications: $e");
    }
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> notificationStrings =
          _notifications.map((notification) {
            return '${notification.title}|${notification.message}|${notification.timestamp.toIso8601String()}|${notification.isRead}|${notification.type}';
          }).toList();

      await prefs.setStringList('notifications', notificationStrings);
    } catch (e) {
      developer.log("Error saving notifications: $e");
    }
  }

  Future<void> _markAsRead(int index) async {
    setState(() {
      _notifications[index].isRead = true;
    });

    try {
      await _saveNotifications();
    } catch (e) {
      developer.log("Error saving notification status: $e");
    }
  }

  Future<void> _deleteNotification(int index) async {
    setState(() {
      _notifications.removeAt(index);
    });

    try {
      await _saveNotifications();
    } catch (e) {
      developer.log("Error saving notifications after delete: $e");
    }
  }

  void _showNotificationDetails(NotificationItem notification) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(notification.title),
            content: Text(notification.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () {
                showDialog(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Clear All Notifications'),
                        content: const Text(
                          'Are you sure you want to delete all notifications?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () {
                              _clearAllNotifications();
                              Navigator.of(context).pop();
                            },
                            child: const Text('DELETE ALL'),
                          ),
                        ],
                      ),
                );
              },
              tooltip: 'Clear all notifications',
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
              ? const Center(
                child: Text('No notifications', style: TextStyle(fontSize: 16)),
              )
              : ListView.builder(
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  return Dismissible(
                    key: Key(
                      'notification_${index}_${notification.timestamp.millisecondsSinceEpoch}',
                    ),
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    direction: DismissDirection.endToStart,
                    onDismissed: (direction) {
                      _deleteNotification(index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Notification deleted'),
                          action: SnackBarAction(
                            label: 'UNDO',
                            onPressed: () {
                              setState(() {
                                _notifications.insert(index, notification);
                                _saveNotifications();
                              });
                            },
                          ),
                        ),
                      );
                    },
                    child: ListTile(
                      title: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight:
                              notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTimestamp(notification.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      leading: CircleAvatar(
                        backgroundColor:
                            notification.isRead
                                ? Colors.grey
                                : Theme.of(context).primaryColor,
                        child: const Icon(
                          Icons.notifications,
                          color: Colors.white,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          notification.isRead
                              ? Icons.more_horiz
                              : Icons.mark_email_read,
                          color: Colors.grey[600],
                        ),
                        onPressed: () {
                          if (!notification.isRead) {
                            _markAsRead(index);
                          }
                        },
                      ),
                      onTap: () {
                        // Mark as read if it's not already
                        if (!notification.isRead) {
                          _markAsRead(index);
                        }
                        // Show notification details
                        _showNotificationDetails(notification);
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  );
                },
              ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      // Format as date if older than a week
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}

// You can add a helper class to add notifications from anywhere in your app
class NotificationService {
  // Flutter local notifications plugin instance
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notification plugin
  static Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
        developer.log("Notification tapped: ${details.payload}");
      },
    );
  }

  // Request notification permissions explicitly
  static Future<void> requestNotificationPermissions() async {
    try {
      // For iOS, permissions are requested during initialization
      // For Android, we'll show notifications anyway but log that permissions are needed
      developer.log("Ensuring notification permissions are granted");

      // For Android 13+ (API level 33), we'll see if permission requests are implemented in future versions
      // Currently, most Flutter apps handle this through the app settings

      // Additional debug log to help troubleshoot
      developer.log(
        "Make sure to enable notifications in your device settings if they don't appear",
      );
    } catch (e) {
      developer.log("Error requesting notification permissions: $e");
    }
  }

  // Show system notification
  static Future<void> showSystemNotification({
    required String title,
    required String message,
    required String type,
  }) async {
    try {
      developer.log(
        "Showing system notification: $title - $message (Type: $type)",
      );

      // Define notification details with high importance
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'vehicle_tracker_alerts', // channel id
            'Vehicle Alerts', // channel name
            channelDescription:
                'High priority alerts from your vehicle tracker',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            icon: '@mipmap/ic_launcher',
            color: Color.fromARGB(255, 255, 0, 0), // Red color for alerts
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Get unique ID for notification
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Show the notification
      await _notificationsPlugin.show(
        notificationId,
        title,
        message,
        platformDetails,
        payload: type,
      );

      developer.log("System notification sent successfully: $title");
    } catch (e) {
      developer.log("Error showing system notification: $e");
    }
  }

  static Future<void> addNotification({
    required String title,
    required String message,
    String type = 'general',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> existingNotifications =
          prefs.getStringList('notifications') ?? [];

      final newNotification =
          '$title|$message|${DateTime.now().toIso8601String()}|false|$type';
      existingNotifications.add(newNotification);

      await prefs.setStringList('notifications', existingNotifications);

      developer.log("Notification added: $title (Type: $type)");
    } catch (e) {
      developer.log("Error adding notification: $e");
    }
  }

  // Show a popup notification
  static void showPopupNotification(
    BuildContext context,
    String title,
    String message, {
    String type = 'general',
  }) {
    // Add the notification to storage
    addNotification(title: title, message: message, type: type);

    // Show system notification
    showSystemNotification(title: title, message: message, type: type);

    // Show popup
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE'),
              ),
            ],
          ),
    );
  }

  // Add a method to handle accident notifications
  static void handleAccidentNotification(
    BuildContext context,
    bool accidentStatus,
    String location,
  ) {
    if (accidentStatus) {
      // Log the alert for debugging
      developer.log(
        'Showing accident alert notification for location: $location',
      );

      // Show the notification with high priority
      showPopupNotification(
        context,
        '⚠️ ACCIDENT ALERT ⚠️',
        'Vehicle has reported an accident at location: $location\nPlease check immediately!',
        type: 'accident',
      );

      // Also show a snackbar for immediate attention
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ACCIDENT ALERT: Vehicle reported accident at $location',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
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
    }
  }

  // Add a method to handle theft detection notifications
  static void handleTheftNotification(
    BuildContext context,
    bool theftStatus,
    String location,
  ) {
    if (theftStatus) {
      showPopupNotification(
        context,
        '🚨 THEFT ALERT 🚨',
        'Possible theft detected! Vehicle has crossed geofence boundaries at location: $location',
        type: 'theft',
      );
    }
  }
}
