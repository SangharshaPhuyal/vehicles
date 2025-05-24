import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences.dart';
import 'auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  late IO.Socket socket;
  bool isConnected = false;

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  Future<void> initializeSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final authService = AuthService(prefs);
    final token = await authService.getToken();

    socket = IO.io('http://your-api-base-url', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
    });

    socket.onConnect((_) {
      print('Socket connected');
      isConnected = true;
    });

    socket.onDisconnect((_) {
      print('Socket disconnected');
      isConnected = false;
    });

    socket.onError((error) {
      print('Socket error: $error');
    });

    socket.connect();
  }

  void shareLocation(Map<String, dynamic> location) {
    if (isConnected) {
      socket.emit('share_location', location);
    }
  }

  void listenToLocationUpdates(Function(Map<String, dynamic>) onLocationUpdate) {
    socket.on('location_update', (data) {
      onLocationUpdate(data);
    });
  }

  void joinRoom(String roomId) {
    if (isConnected) {
      socket.emit('join_room', {'room': roomId});
    }
  }

  void leaveRoom(String roomId) {
    if (isConnected) {
      socket.emit('leave_room', {'room': roomId});
    }
  }

  void sendMessage(String roomId, String message) {
    if (isConnected) {
      socket.emit('message', {
        'room': roomId,
        'message': message,
      });
    }
  }

  void listenToMessages(Function(Map<String, dynamic>) onMessageReceived) {
    socket.on('message', (data) {
      onMessageReceived(data);
    });
  }

  void disconnect() {
    socket.disconnect();
    isConnected = false;
  }
} 