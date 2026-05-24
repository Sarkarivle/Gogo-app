import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';
import 'premium_service.dart';
import 'call_service.dart';

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
  Timer? _reconnectTimer;

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
    _socket?.dispose();
    _socket = IO.io(ApiService.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 50,
      'reconnectionDelay': 2000,
      'timeout': 10000,
    });

    _socket!.onConnect((_) {
      debugPrint('⚡ Socket Connected: ${_socket!.id}');
      connectionStatus.value = true;
      _setOnline();
      if (_activeRoomId != null) {
        _socket!.emit('join_room', _activeRoomId);
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ Socket Disconnected');
      connectionStatus.value = false;
    });

    _socket!.onConnectError((err) => debugPrint('⚠️ Connect Error: $err'));
    _socket!.onError((err) => debugPrint('⚠️ Socket Error: $err'));

    _socket!.on('user_status_change', (data) {
      final phone = data['phone'];
      final isOnline = data['isOnline'];
      final updated = Map<String, bool>.from(onlineUsers.value);
      updated[phone] = isOnline;
      onlineUsers.value = updated;
    });

    _socket!.on('display_typing', (data) {
      final phone = data['phone'];
      if (phone != null) {
        final updated = Map<String, bool>.from(typingUsers.value);
        updated[phone] = true;
        typingUsers.value = updated;
      }
    });

    _socket!.on('hide_typing', (data) {
      final phone = data['phone'];
      if (phone != null) {
        final updated = Map<String, bool>.from(typingUsers.value);
        updated[phone] = false;
        typingUsers.value = updated;
      }
    });

    _socket!.on('receive_message', (data) {
      _messageController.add(data);
      _eventController.add({'event': 'receive_message', 'data': data});
    });
    
    _socket!.on('message_delivered', (data) => _eventController.add({'event': 'message_delivered', 'data': data}));
    _socket!.on('message_opened', (data) => _eventController.add({'event': 'message_opened', 'data': data}));
    _socket!.on('chat_seen_update', (data) => _eventController.add({'event': 'chat_seen_update', 'data': data}));
    _socket!.on('message_deleted', (data) => _eventController.add({'event': 'message_deleted', 'data': data}));
    _socket!.on('message_edited', (data) => _eventController.add({'event': 'message_edited', 'data': data}));
    _socket!.on('message_deleted_for_everyone', (data) => _eventController.add({'event': 'message_deleted_for_everyone', 'data': data}));
    _socket!.on('moderation_state_updated', (data) => _eventController.add({'event': 'moderation_state_updated', 'data': data}));
    _socket!.on('chat_status_update', (data) => _eventController.add({'event': 'chat_status_update', 'data': data}));
    _socket!.on('unread_update', (data) => _eventController.add({'event': 'unread_update', 'data': data}));

    // --- CALL EVENTS ---
    _socket!.on('incoming_call', (data) => _eventController.add({'event': 'incoming_call', 'data': data}));
    _socket!.on('call_accepted', (data) => _eventController.add({'event': 'call_accepted', 'data': data}));
    _socket!.on('call_rejected', (data) => _eventController.add({'event': 'call_rejected', 'data': data}));
    _socket!.on('call_ended', (data) => _eventController.add({'event': 'call_ended', 'data': data}));
    _socket!.on('call_busy', (data) => _eventController.add({'event': 'call_busy', 'data': data}));
    _socket!.on('call_ringing', (data) => _eventController.add({'event': 'call_ringing', 'data': data}));
    _socket!.on('call_timeout', (data) => _eventController.add({'event': 'call_timeout', 'data': data}));
    _socket!.on('sdp_offer', (data) => _eventController.add({'event': 'sdp_offer', 'data': data}));
    _socket!.on('sdp_answer', (data) => _eventController.add({'event': 'sdp_answer', 'data': data}));
    _socket!.on('ice_candidate', (data) => _eventController.add({'event': 'ice_candidate', 'data': data}));

    // --- REALTIME ADMIN ACTIONS ---
    _socket!.on('profile_sync_required', (data) {
      debugPrint('🔄 Admin forced profile sync: $data');
      _eventController.add({'event': 'profile_sync_required', 'data': data});
    });

    _socket!.on('force_action', (data) {
      debugPrint('🚫 Admin forced action: $data');
      if (data['action'] == 'LOGOUT') {
        _eventController.add({'event': 'force_logout', 'data': data});
      }
    });

    _socket!.on('admin_alert', (data) {
      debugPrint('⚠️ Admin direct alert: $data');
      _eventController.add({'event': 'admin_alert', 'data': data});
    });

    if (_currentUserPhone != null) {
      _socket!.on('premium_update_$_currentUserPhone', (data) {
        PremiumService().updatePremiumStatus(true);
        _eventController.add({'event': 'premium_update', 'data': data});
      });
    }
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
      debugPrint('⚠️ Cannot emit $event: Socket disconnected. Attempting reconnect...');
      _socket?.connect();
    }
  }

  void joinRoom(String roomId) {
    _activeRoomId = roomId;
    if (_socket != null && _socket!.connected) {
      _socket!.emit('join_room', roomId);
    }
  }

  void leaveRoom() {
    _activeRoomId = null;
    // We don't necessarily need to tell the server we left, 
    // but the next join_room will switch the room on server side if implemented that way.
  }

  IO.Socket? get socket => _socket;
  String? get currentUserPhone => _currentUserPhone;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket?.connect();
      _setOnline();
    } else if (state == AppLifecycleState.paused) {
      // Optional: Set offline on pause if you want strict presence
    }
  }

  void updateCurrentUser(String phone) {
    if (_currentUserPhone != phone) {
      _currentUserPhone = phone;
      _setOnline();
      
      // Re-bind premium update listener for new phone
      if (_socket != null) {
        _socket!.off('premium_update'); // Clear old ones if any generic ones existed
        _socket!.on('premium_update_$phone', (data) {
          PremiumService().updatePremiumStatus(true);
          _eventController.add({'event': 'premium_update', 'data': data});
        });
      }
    }
  }

  void setTyping(String phone, bool isTyping) {
    final updated = Map<String, bool>.from(typingUsers.value);
    updated[phone] = isTyping;
    typingUsers.value = updated;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.dispose();
    _reconnectTimer?.cancel();
    _messageController.close();
    _eventController.close();
    _isInitialized = false;
  }
}
