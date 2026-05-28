import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/socket_service.dart';
import 'random_socket_service.dart';
import 'random_rtc_service.dart';
import '../screens/random_searching_screen.dart';
import '../screens/random_match_screen.dart';
import '../screens/random_video_call_screen.dart';
import '../screens/random_live_intro_screen.dart';
import '../../services/chat_repository.dart';
import '../../main.dart';
import '../../utils/phone_utils.dart';

enum RandomRoomState { idle, searching, matched, inCall }

class RandomRoomService with WidgetsBindingObserver {
  static final RandomRoomService _instance = RandomRoomService._internal();
  factory RandomRoomService() => _instance;
  RandomRoomService._internal();

  final ValueNotifier<RandomRoomState> state = ValueNotifier(RandomRoomState.idle);
  final ValueNotifier<bool> remoteVideoOff = ValueNotifier(false);
  String? currentRoomId;
  String? partnerId;
  String? role;
  StreamSubscription? _socketSub;
  Timer? _searchTimer;

  // Signaling Queue for race condition prevention
  final List<Map<String, dynamic>> _signalingQueue = [];

  void init() {
    RandomSocketService().init();
    _socketSub?.cancel();
    _socketSub = RandomSocketService().eventStream.listen(_handleSocketEvent);
    
    // Listen for app lifecycle to cut call on background
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (this.state.value == RandomRoomState.inCall || this.state.value == RandomRoomState.matched) {
        debugPrint("[RandomRoom] App moved to background. Cutting call.");
        final context = MyApp.navigatorKey.currentContext;
        if (context != null) {
          endCall(context);
        }
      }
    }
  }

  void startSearch(BuildContext context) {
    final userId = SocketService().currentUserPhone;
    if (userId == null) return;

    if (state.value == RandomRoomState.searching) return;

    state.value = RandomRoomState.searching;
    
    final randomDelay = 1500 + Random().nextInt(2500);
    debugPrint("[RandomRoom] UI Animation start. API delay: ${randomDelay}ms");

    _searchTimer?.cancel();
    _searchTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (state.value == RandomRoomState.searching) {
        RandomSocketService().findPartner(userId);
      }
    });
  }

  void _handleSocketEvent(Map<String, dynamic> event) {
    final type = event['event'];
    final data = event['data'];

    switch (type) {
      case 'random_match_found':
        _onMatchFound(data);
        break;
      case 'random_partner_left':
        _onPartnerLeft();
        break;
      case 'random_offer':
        _queueOrProcessSignaling({'type': 'offer', 'data': data['offer']});
        break;
      case 'random_answer':
        _queueOrProcessSignaling({'type': 'answer', 'data': data['answer']});
        break;
      case 'random_candidate':
        _queueOrProcessSignaling({'type': 'candidate', 'data': data['candidate']});
        break;
      case 'random_call_state_sync':
        remoteVideoOff.value = data['isVideoOff'] ?? false;
        break;
      case 'random_partner_blocked':
        _onPartnerBlocked();
        break;
    }
  }

  Future<void> _queueOrProcessSignaling(Map<String, dynamic> msg) async {
    if (!RandomRtcService().isInitialized || state.value != RandomRoomState.inCall) {
      debugPrint("[RTC] Signaling (${msg['type']}) received but RTC not ready. Queuing...");
      _signalingQueue.add(msg);
      return;
    }

    try {
      switch (msg['type']) {
        case 'offer':
          await _processOffer(msg['data']);
          break;
        case 'answer':
          await _processAnswer(msg['data']);
          break;
        case 'candidate':
          await _processCandidate(msg['data']);
          break;
      }
    } catch (e) {
      debugPrint("[RTC] Error processing ${msg['type']}: $e");
    }
  }

  void _onMatchFound(Map<String, dynamic> data) async {
    currentRoomId = data['roomId'];
    partnerId = PhoneUtils.normalize(data['partnerId']);
    role = data['role'];
    state.value = RandomRoomState.matched;

    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RandomMatchScreen()),
    );

    // Give some time for animation
    await Future.delayed(const Duration(milliseconds: 2500));
    
    if (state.value != RandomRoomState.matched) return;

    if (context.mounted) {
       Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RandomVideoCallScreen()),
      );
    }

    state.value = RandomRoomState.inCall;

    try {
      if (currentRoomId == null || partnerId == null) {
        throw Exception("Room ID or Partner ID is missing");
      }

      // Initialize RTC
      await RandomRtcService().initLocalStream();
      await RandomRtcService().initializePeerConnection(currentRoomId!, partnerId!);

      // Process queued signaling messages
      debugPrint("[RTC] Processing ${_signalingQueue.length} queued signals");
      while (_signalingQueue.isNotEmpty) {
        final msg = _signalingQueue.removeAt(0);
        await _queueOrProcessSignaling(msg);
      }

      if (role == 'caller') {
        final offer = await RandomRtcService().createOffer();
        if (offer != null) {
          RandomSocketService().emitOffer(currentRoomId!, partnerId!, {
            'sdp': offer.sdp,
            'type': offer.type,
          });
        }
      }
    } catch (e) {
      debugPrint("[RTC] Initialization Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection Error. Trying next...")));
        nextPartner(context);
      }
    }
  }

  Future<void> _processOffer(dynamic offerData) async {
    if (currentRoomId == null || partnerId == null) return;
    
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await RandomRtcService().setRemoteDescription(offer);
    final answer = await RandomRtcService().createAnswer();
    if (answer != null) {
      RandomSocketService().emitAnswer(currentRoomId!, partnerId!, {
        'sdp': answer.sdp,
        'type': answer.type,
      });
    }
  }

  Future<void> _processAnswer(dynamic answerData) async {
    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await RandomRtcService().setRemoteDescription(answer);
  }

  Future<void> _processCandidate(dynamic candidateData) async {
    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    await RandomRtcService().addCandidate(candidate);
  }

  void _onPartnerLeft() {
    debugPrint("[RandomRoom] Partner left. Navigating to searching...");
    _cleanupFull();
    
    final context = MyApp.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
      );
      startSearch(context);
    }
  }

  void _onPartnerBlocked() {
    debugPrint("[RandomRoom] Partner blocked me. Exiting...");
    _cleanupFull();
    
    final context = MyApp.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Partner disconnected.")),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RandomLiveIntroScreen()),
        (route) => route.isFirst,
      );
    }
  }

  void nextPartner(BuildContext context) {
    final userId = SocketService().currentUserPhone;
    if (userId == null) return;

    _cleanupFull();
    RandomSocketService().nextPartner(userId);
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
    );
    startSearch(context);
  }

  void endCall(BuildContext context) {
    debugPrint("[RandomRoom] End Call requested. Full Exit.");
    final userId = SocketService().currentUserPhone;
    if (userId == null) return;

    // Strict Cleanup Order
    // 1. Notify partner & backend room cleanup first
    RandomSocketService().leaveRoom(userId);
    
    // 2. Full RTC & Local State Cleanup
    _cleanupFull();
    
    if (context.mounted) {
       Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RandomLiveIntroScreen()),
        (route) => route.isFirst,
      );
    }
  }

  void blockAndExit(BuildContext context, {required bool isReport}) async {
    final String? myPhone = SocketService().currentUserPhone;
    final String? pId = partnerId;
    final String? rId = currentRoomId;
    
    debugPrint("[RandomRoom] Block and Exit triggered. Redirecting to Search.");

    if (myPhone != null && pId != null) {
      // 1. Backend Block Relation
      ChatRepository().blockUser(
        blockerPhone: myPhone,
        blockedPhone: pId,
        isReported: isReport,
        reason: isReport ? "Random Call Report" : "No reason"
      );
      
      // 2. Emit Socket Block Event
      if (rId != null) {
        RandomSocketService().emitBlock(rId, pId);
      }
      
      // 3. Inform partner & backend room cleanup
      RandomSocketService().leaveRoom(myPhone);
      
      // 4. Full RTC & Local State Cleanup
      _cleanupFull();
      
      // 5. Direct to Search Screen
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
        );
        startSearch(context);
      }
    }
  }

  void _cleanupFull() {
    debugPrint("[RandomRoom] Performing Full Cleanup...");
    _searchTimer?.cancel();
    _signalingQueue.clear();
    RandomRtcService().dispose();
    currentRoomId = null;
    partnerId = null;
    role = null;
    state.value = RandomRoomState.idle;
    remoteVideoOff.value = false;
  }

  void dispose() {
    _socketSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cleanupFull();
  }
}
