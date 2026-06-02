import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/network/webrtc_manager.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/core/services/permission_manager.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/main.dart';
import 'package:gogo/features/call/screens/call_screen.dart';

enum CallState { idle, ringing, connecting, connected, ended }

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  CallState _state = CallState.idle;
  CallState get state => _state;
  String? get myPhone => SocketService().currentUserPhone;

  String? _remotePhone;
  String? _remoteName;
  bool _isVideo = false;
  bool _isOutgoing = false;
  bool _remoteIsVideoOff = false;
  bool get remoteIsVideoOff => _remoteIsVideoOff;
  DateTime? _startTime;
  Timer? _callTimeoutTimer;

  final _webrtc = WebRTCManager();
  
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get stateStream => _stateController.stream;

  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    final socket = SocketService();
    
    // Using a systematic approach to listeners as requested
    socket.eventStream.listen((event) {
      final data = event['data'];
      switch (event['event']) {
        case 'incoming_call':
          _handleIncomingCall(data);
          break;
        case 'call_accepted':
          _handleCallAccepted();
          break;
        case 'call_rejected':
          _handleCallRejected();
          break;
        case 'call_ended':
          _handleCallEnded();
          break;
        case 'sdp_offer':
          _handleSDPOffer(data);
          break;
        case 'sdp_answer':
          _handleSDPAnswer(data);
          break;
        case 'ice_candidate':
          _handleICECandidate(data);
          break;
        case 'call_state_sync':
          _handleCallStateSync(data);
          break;
        case 'call_busy':
          _handleCallRejected(); 
          break;
        case 'call_ringing':
          _handleCallRinging();
          break;
      }
    });
  }

  Future<void> startCall(String remotePhone, String remoteName, {required bool isVideo}) async {
    if (_state != CallState.idle) return;

    debugPrint("[CallService] Starting Call to $remotePhone");
    
    _updateState(CallState.ringing);
    _remotePhone = remotePhone;
    _remoteName = remoteName;
    _isVideo = isVideo;
    _isOutgoing = true;

    final userData = UserRepository().currentUser ?? {};
    final myName = userData['name'] ?? 'User';

    SocketService().emit('initiate_call', {
      'targetPhone': remotePhone,
      'isVideo': isVideo,
      'callerName': myName,
      'callerPhone': SocketService().currentUserPhone,
    });

    _startTimeoutTimer();
    _showCallScreen();
  }

  void _handleIncomingCall(dynamic data) async {
    if (_state != CallState.idle) {
      SocketService().emit('call_busy', {'targetPhone': data['callerPhone']});
      return;
    }

    final myPhone = SocketService().currentUserPhone;
    if (myPhone != null) {
      final blockStatus = await ChatRepository().checkBlockStatus(myPhone, data['callerPhone']);
      if (blockStatus['isBlocked'] == true) {
        SocketService().emit('call_rejected', {'targetPhone': data['callerPhone']});
        return;
      }
    }

    _updateState(CallState.ringing);
    _remotePhone = data['callerPhone'];
    _remoteName = data['callerName'] ?? 'Unknown';
    _isVideo = data['isVideo'] ?? false;
    _isOutgoing = false;

    SocketService().emit('call_ringing', {'targetPhone': _remotePhone});

    _startTimeoutTimer();
    _showCallScreen();
  }

  void _handleCallRinging() {
    if (_state == CallState.ringing && _isOutgoing) {
      debugPrint("🔔 Call is ringing on remote side");
    }
  }

  void _startTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_state == CallState.ringing || _state == CallState.connecting) {
        debugPrint("⏰ Call timed out");
        endCall();
      }
    });
  }

  void _stopTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  void _showCallScreen() {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          remoteName: _remoteName!,
          remotePhone: _remotePhone!,
          isVideo: _isVideo,
          isOutgoing: _isOutgoing,
        ),
      ),
    );
  }

  Future<void> acceptCall() async {
    if (_state != CallState.ringing) return;

    final context = MyApp.navigatorKey.currentContext;
    if (context != null) {
      final hasPermission = await PermissionManager().checkAndRequestCallPermissions(context, isVideo: _isVideo);
      if (!hasPermission) {
        rejectCall();
        return;
      }
    }

    _updateState(CallState.connecting);
    _stopTimeoutTimer();

    SocketService().emit('accept_call', {'targetPhone': _remotePhone});
  }

  void rejectCall() {
    SocketService().emit('reject_call', {'targetPhone': _remotePhone});
    _cleanup();
  }

  void endCall() {
    if (_remotePhone != null) {
      SocketService().emit('end_call', {'targetPhone': _remotePhone});
    }
    _cleanup();
  }

  void _handleCallAccepted() async {
    if (_state != CallState.ringing || !_isOutgoing) return;
    _updateState(CallState.connecting);
    _stopTimeoutTimer();

    // Caller initiates WebRTC
    await _webrtc.initLocalStream(_isVideo);
    if (_remotePhone != null) {
      await _webrtc.initializePeerConnection(_remotePhone!);
      
      final offer = await _webrtc.createOffer();
      SocketService().emit('sdp_offer', {
        'targetPhone': _remotePhone,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
    }
  }

  void _handleCallRejected() {
    _cleanup();
  }

  void _handleCallEnded() {
    _cleanup();
  }

  void _handleSDPOffer(dynamic data) async {
    if (_state != CallState.connecting && _state != CallState.ringing) return;
    if (_remotePhone == null) return;

    _updateState(CallState.connecting);
    
    await _webrtc.initLocalStream(_isVideo);
    await _webrtc.initializePeerConnection(_remotePhone!);
    
    final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
    await _webrtc.setRemoteDescription(offer);
    
    final answer = await _webrtc.createAnswer();
    SocketService().emit('sdp_answer', {
      'targetPhone': _remotePhone,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
    
    _updateState(CallState.connected);
  }

  void _handleSDPAnswer(dynamic data) async {
    if (_state != CallState.connecting) return;
    
    final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
    await _webrtc.setRemoteDescription(answer);
    
    _updateState(CallState.connected);
  }

  void _handleCallStateSync(dynamic data) {
    if (_state != CallState.connected) return;
    _remoteIsVideoOff = data['isVideoOff'] ?? false;
    _stateController.add(_state); 
  }

  void syncState({required bool isMuted, required bool isVideoOff}) {
    if (_state != CallState.connected) return;
    SocketService().emit('call_state_sync', {
      'targetPhone': _remotePhone,
      'isMuted': isMuted,
      'isVideoOff': isVideoOff,
    });
  }

  void _handleICECandidate(dynamic data) async {
    if (_state != CallState.connecting && _state != CallState.connected) return;
    final candidateData = data['candidate'];
    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    await _webrtc.addCandidate(candidate);
  }

  void _updateState(CallState newState) {
    if (newState == CallState.connected) {
      _startTime = DateTime.now();
    }
    _state = newState;
    _stateController.add(_state);
  }

  void _cleanup() {
    debugPrint("[CallService] Cleaning up call session...");
    _stopTimeoutTimer();
    final endState = _state;
    _updateState(CallState.ended);
    
    // Log Call
    final myPhone = SocketService().currentUserPhone;
    if (myPhone != null && _remotePhone != null) {
      int duration = 0;
      if (_startTime != null) {
        duration = DateTime.now().difference(_startTime!).inSeconds;
      }
      
      String status = 'missed';
      if (endState == CallState.connected) status = 'completed';
      if (endState == CallState.ringing && !_isOutgoing) status = 'missed';
      if (endState == CallState.ringing && _isOutgoing) status = 'no_answer';

      ChatRepository().logCall(
        senderPhone: _isOutgoing ? myPhone : _remotePhone!,
        receiverPhone: _isOutgoing ? _remotePhone! : myPhone,
        callType: _isVideo ? 'video' : 'audio',
        duration: duration,
        status: status,
      );
    }

    _webrtc.dispose();
    _remotePhone = null;
    _remoteName = null;
    _startTime = null;
    _remoteIsVideoOff = false;
    
    // Reset to idle after a small delay to allow UI transitions
    Future.delayed(const Duration(milliseconds: 500), () {
      _updateState(CallState.idle);
    });
  }
}
