import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _currentUserPhone;
  
  // Realtime Presence State
  final ValueNotifier<Map<String, bool>> onlineUsers = ValueNotifier({});
  final ValueNotifier<Map<String, bool>> typingUsers = ValueNotifier({});
  final ValueNotifier<bool> connectionStatus = ValueNotifier(false);

  // Stream Controllers for Events
  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  bool _isInitialized = false;

  void init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _loadUserData();
    _connectSocket();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      final userData = jsonDecode(userDataStr);
      _currentUserPhone = userData['phone'];
    }
  }

  void _connectSocket() {
    _socket = IO.io('http://72.61.170.181:5000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 2000,
    });

    _socket!.onConnect((_) {
      debugPrint('Socket Connected: ${_socket!.id}');
      connectionStatus.value = true;
      _setOnline();
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket Disconnected');
      connectionStatus.value = false;
    });

    _socket!.on('user_status_change', (data) {
      final phone = data['phone'];
      final isOnline = data['isOnline'];
      final updated = Map<String, bool>.from(onlineUsers.value);
      updated[phone] = isOnline;
      onlineUsers.value = updated;
    });

    _socket!.on('display_typing', (data) {
      final phone = data['phone'];
      final updated = Map<String, bool>.from(typingUsers.value);
      updated[phone] = true;
      typingUsers.value = updated;
    });

    _socket!.on('hide_typing', (data) {
      final phone = data['phone'];
      final updated = Map<String, bool>.from(typingUsers.value);
      updated[phone] = false;
      typingUsers.value = updated;
    });

    _socket!.on('receive_message', (data) => _messageController.add(data));
    
    // Generic event listeners
    _socket!.on('message_delivered', (data) => _eventController.add({'event': 'message_delivered', 'data': data}));
    _socket!.on('message_opened', (data) => _eventController.add({'event': 'message_opened', 'data': data}));
    _socket!.on('chat_seen_update', (data) => _eventController.add({'event': 'chat_seen_update', 'data': data}));
    _socket!.on('message_deleted', (data) => _eventController.add({'event': 'message_deleted', 'data': data}));
    _socket!.on('message_edited', (data) => _eventController.add({'event': 'message_edited', 'data': data}));
    _socket!.on('chat_status_update', (data) => _eventController.add({'event': 'chat_status_update', 'data': data}));
    _socket!.on('unread_update', (data) => _eventController.add({'event': 'unread_update', 'data': data}));
  }

  void _setOnline() {
    if (_currentUserPhone != null && _socket != null && _socket!.connected) {
      _socket!.emit('set_online', _currentUserPhone);
    }
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  IO.Socket? get socket => _socket;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_socket != null && !_socket!.connected) {
        _socket!.connect();
      } else {
        _setOnline();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // In a real production app, we might want to emit a 'set_away' event
      // but for now, the socket disconnect will handle it automatically after timeout.
    }
  }

  void updateCurrentUser(String phone) {
    _currentUserPhone = phone;
    _setOnline();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.dispose();
    _messageController.close();
    _eventController.close();
    _isInitialized = false;
  }
}
