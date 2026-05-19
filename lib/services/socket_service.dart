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
  String? _activeRoomId;
  
  final ValueNotifier<Map<String, bool>> onlineUsers = ValueNotifier({});
  final ValueNotifier<Map<String, bool>> typingUsers = ValueNotifier({});
  final ValueNotifier<bool> connectionStatus = ValueNotifier(false);

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
      'reconnectionAttempts': 20,
      'reconnectionDelay': 1000,
    });

    _socket!.onConnect((_) {
      debugPrint('⚡ Socket Connected: ${_socket!.id}');
      connectionStatus.value = true;
      _setOnline();
      if (_activeRoomId != null) {
        _socket!.emit('join_room', _activeRoomId);
        debugPrint('🏠 Re-joined active room: $_activeRoomId');
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ Socket Disconnected');
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
      final updated = Map<String, bool>.from(typingUsers.value);
      updated[data['phone']] = true;
      typingUsers.value = updated;
    });

    _socket!.on('hide_typing', (data) {
      final updated = Map<String, bool>.from(typingUsers.value);
      updated[data['phone']] = false;
      typingUsers.value = updated;
    });

    _socket!.on('receive_message', (data) {
      debugPrint('📩 New message received via socket');
      _messageController.add(data);
    });
    
    _socket!.on('message_delivered', (data) => _eventController.add({'event': 'message_delivered', 'data': data}));
    _socket!.on('message_opened', (data) => _eventController.add({'event': 'message_opened', 'data': data}));
    _socket!.on('chat_seen_update', (data) => _eventController.add({'event': 'chat_seen_update', 'data': data}));
    _socket!.on('message_deleted', (data) => _eventController.add({'event': 'message_deleted', 'data': data}));
    _socket!.on('message_edited', (data) => _eventController.add({'event': 'message_edited', 'data': data}));
    _socket!.on('message_deleted_for_everyone', (data) => _eventController.add({'event': 'message_deleted_for_everyone', 'data': data}));
    _socket!.on('chat_status_update', (data) => _eventController.add({'event': 'chat_status_update', 'data': data}));
  }

  void _setOnline() {
    if (_currentUserPhone != null && _socket != null && _socket!.connected) {
      _socket!.emit('set_online', _currentUserPhone);
    }
  }

  void emit(String event, dynamic data, [Function? ack]) {
    if (_socket != null && _socket!.connected) {
      if (ack != null) {
        _socket!.emitWithAck(event, data, ack: ack);
      } else {
        _socket!.emit(event, data);
      }
    } else {
      debugPrint('⚠️ Cannot emit $event: Socket disconnected');
      // If we emit a message while disconnected, we should try to reconnect
      _socket?.connect();
    }
  }

  void joinRoom(String roomId) {
    _activeRoomId = roomId;
    if (_socket != null && _socket!.connected) {
      _socket!.emit('join_room', roomId);
    }
  }

  void markChatSeen(String myPhone, String otherPhone) {
    emit('mark_chat_seen', {'myPhone': myPhone, 'otherPhone': otherPhone});
  }

  void leaveRoom() {
    _activeRoomId = null;
  }

  IO.Socket? get socket => _socket;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket?.connect();
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
