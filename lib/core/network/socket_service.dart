import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

import 'package:gogo/core/services/presence_manager.dart';
import 'package:gogo/core/services/typing_manager.dart';

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  String? _currentUserPhone;
  String? _activeRoomId;
  String? get activeRoomId => _activeRoomId;
  
  final typingUsers = ValueNotifier<Map<String, bool>>({}); // Legacy support for now
  final connectionStatus = ValueNotifier<bool>(false);

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
    await UserRepository().initialize(); // Ensure repo is initialized
    final current = UserRepository().currentUser;
    if (current != null) {
      _currentUserPhone = PhoneUtils.normalize(current['phone']);
    }
  }

  void _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    _socket?.dispose();
    _socket = io.io(ApiService.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 50,
      'reconnectionDelay': 2000,
      'timeout': 10000,
      'auth': token != null ? {'token': token} : null,
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
      
      // Update PresenceManager for granular UI updates
      PresenceManager().updateStatus(phone, isOnline);
    });

    _socket!.on('display_typing', (data) => _setTypingStatus(data['phone'], true));
    _socket!.on('hide_typing', (data) => _setTypingStatus(data['phone'], false));

    _socket!.on('receive_message', (data) {
      // Clear typing status for the sender when a message is received
      if (data['senderPhone'] != null) {
        _setTypingStatus(data['senderPhone'], false);
      }

      _messageController.add(data);
      _eventController.add({'event': 'receive_message', 'data': data});

      if (_activeRoomId != data['roomId']) {
        NotificationService.showLocalNotificationFromSocket(data);
      }
    });
    
    _socket!.on('message_delivered', (data) => _eventController.add({'event': 'message_delivered', 'data': data}));
    _socket!.on('pending_messages_delivered', (data) => _eventController.add({'event': 'pending_messages_delivered', 'data': data}));
    _socket!.on('global_delivery_update', (data) => _eventController.add({'event': 'global_delivery_update', 'data': data}));
    _socket!.on('message_opened', (data) => _eventController.add({'event': 'message_opened', 'data': data}));
    _socket!.on('chat_seen_update', (data) => _eventController.add({'event': 'chat_seen_update', 'data': data}));
    _socket!.on('message_deleted', (data) => _eventController.add({'event': 'message_deleted', 'data': data}));
    _socket!.on('message_deleted_global', (data) => _eventController.add({'event': 'message_deleted', 'data': data}));
    _socket!.on('message_edited', (data) => _eventController.add({'event': 'message_edited', 'data': data}));
    _socket!.on('message_deleted_for_everyone', (data) => _eventController.add({'event': 'message_deleted_for_everyone', 'data': data}));
    _socket!.on('moderation_state_updated', (data) => _eventController.add({'event': 'moderation_state_updated', 'data': data}));
    _socket!.on('chat_status_update', (data) => _eventController.add({'event': 'chat_status_update', 'data': data}));
    _socket!.on('unread_update', (data) => _eventController.add({'event': 'unread_update', 'data': data}));
    _socket!.on('conversation_update', (data) => _eventController.add({'event': 'conversation_update', 'data': data}));
    _socket!.on('user_deactivated', (data) => _eventController.add({'event': 'user_deactivated', 'data': data}));
    _socket!.on('user_reactivated', (data) => _eventController.add({'event': 'user_reactivated', 'data': data}));

    // --- CALL EVENTS ---
    _socket!.on('incoming_call', (data) {
      _eventController.add({'event': 'incoming_call', 'data': data});
      // Show notification if app is in background/other screen
      NotificationService.showCallNotification(data);
    });
    _socket!.on('call_accepted', (data) => _eventController.add({'event': 'call_accepted', 'data': data}));
    _socket!.on('call_rejected', (data) => _eventController.add({'event': 'call_rejected', 'data': data}));
    _socket!.on('call_ended', (data) => _eventController.add({'event': 'call_ended', 'data': data}));
    _socket!.on('call_busy', (data) => _eventController.add({'event': 'call_busy', 'data': data}));
    _socket!.on('call_ringing', (data) => _eventController.add({'event': 'call_ringing', 'data': data}));
    _socket!.on('call_timeout', (data) => _eventController.add({'event': 'call_timeout', 'data': data}));
    _socket!.on('sdp_offer', (data) => _eventController.add({'event': 'sdp_offer', 'data': data}));
    _socket!.on('sdp_answer', (data) => _eventController.add({'event': 'sdp_answer', 'data': data}));
    _socket!.on('ice_candidate', (data) => _eventController.add({'event': 'ice_candidate', 'data': data}));
    _socket!.on('random_match_found', (data) => _eventController.add({'event': 'random_match_found', 'data': data}));

    // --- REALTIME ADMIN ACTIONS ---
    _socket!.on('profile_sync_required', (data) async {
      debugPrint('🔄 Admin forced profile sync: $data');
      _eventController.add({'event': 'profile_sync_required', 'data': data});
      await PremiumService().refreshAccessState();
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

    _socket!.on('freemium_config_update', (data) async {
      debugPrint('🎁 Freemium config updated via socket');
      await PremiumService().refreshAccessState();
    });

    _socket!.on('premium_status_refresh', (data) async {
      debugPrint('⚡ Premium status refresh triggered via socket');
      _eventController.add({'event': 'premium_status_refresh', 'data': data});
      await PremiumService().refreshAccessState();
    });
    
    if (_currentUserPhone != null) {
      _socket!.on('premium_update_$_currentUserPhone', (data) async {
        debugPrint('💎 Premium update received for user: $_currentUserPhone');
        await PremiumService().refreshAccessState();
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

  io.Socket? get socket => _socket;
  String? get currentUserPhone => _currentUserPhone;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket?.connect();
      _setOnline();
      // FAST SYNC: Check toggle status immediately when app is opened/resumed
      PremiumService().refreshAccessState();
    }
  }

  void updateCurrentUser(String phone) {
    final normalized = PhoneUtils.normalize(phone);
    if (_currentUserPhone != normalized && normalized != null) {
      _currentUserPhone = normalized;
      _connectSocket(); // Reconnect to refresh token and identity
    }
  }

  void _setTypingStatus(String? phone, bool isTyping) {
    if (phone == null) return;
    TypingManager().setTyping(phone, isTyping);
    
    // Support legacy listeners for a short transition period
    final String? normalizedPhone = PhoneUtils.normalize(phone);
    if (normalizedPhone == null) return;
    final updated = Map<String, bool>.from(typingUsers.value);
    updated[normalizedPhone] = isTyping;
    typingUsers.value = updated;
  }

  void setTyping(String phone, bool isTyping) => _setTypingStatus(phone, isTyping);

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.dispose();
    _reconnectTimer?.cancel();
    _messageController.close();
    _eventController.close();
    _isInitialized = false;
  }
}
