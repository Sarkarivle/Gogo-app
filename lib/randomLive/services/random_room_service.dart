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
import '../../main.dart';

enum RandomRoomState { idle, searching, matched, inCall }

class RandomRoomService {
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
  dynamic _pendingOffer;

  void init() {
    RandomSocketService().init();
    _socketSub?.cancel();
    _socketSub = RandomSocketService().eventStream.listen(_handleSocketEvent);
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
        _onOfferReceived(data['offer']);
        break;
      case 'random_answer':
        _onAnswerReceived(data['answer']);
        break;
      case 'random_candidate':
        _onCandidateReceived(data['candidate']);
        break;
      case 'random_call_state_sync':
        remoteVideoOff.value = data['isVideoOff'] ?? false;
        break;
    }
  }

  void _onMatchFound(Map<String, dynamic> data) async {
    currentRoomId = data['roomId'];
    partnerId = data['partnerId'];
    role = data['role'];
    state.value = RandomRoomState.matched;

    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RandomMatchScreen()),
    );

    await Future.delayed(const Duration(milliseconds: 2500));
    
    if (state.value != RandomRoomState.matched) return;

    if (context.mounted) {
       Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RandomVideoCallScreen()),
      );
    }

    // Initialize RTC
    await RandomRtcService().initLocalStream();
    await RandomRtcService().initializePeerConnection(currentRoomId!, partnerId!);

    // Process pending offer if any
    if (_pendingOffer != null) {
      debugPrint("[RTC] Processing queued offer after initialization");
      await _processOffer(_pendingOffer);
      _pendingOffer = null;
    }

    if (role == 'caller') {
      final offer = await RandomRtcService().createOffer();
      RandomSocketService().emitOffer(currentRoomId!, partnerId!, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    }
    state.value = RandomRoomState.inCall;
  }

  void _onOfferReceived(dynamic offerData) async {
    if (!RandomRtcService().isInitialized) {
      debugPrint("[RTC] Offer received but RTC not ready. Queuing...");
      _pendingOffer = offerData;
      return;
    }
    await _processOffer(offerData);
  }

  Future<void> _processOffer(dynamic offerData) async {
    if (currentRoomId == null || partnerId == null) return;
    
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await RandomRtcService().setRemoteDescription(offer);
    final answer = await RandomRtcService().createAnswer();
    RandomSocketService().emitAnswer(currentRoomId!, partnerId!, {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  void _onAnswerReceived(dynamic answerData) async {
    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await RandomRtcService().setRemoteDescription(answer);
  }

  void _onCandidateReceived(dynamic candidateData) async {
    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    await RandomRtcService().addCandidate(candidate);
  }

  void _onPartnerLeft() {
    _cleanupFull();
    
    final context = MyApp.navigatorKey.currentContext;
    if (context != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
      );
      startSearch(context);
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
    final userId = SocketService().currentUserPhone;
    if (userId == null) return;

    _cleanupFull();
    RandomSocketService().leaveRoom(userId);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _cleanupFull() {
    _searchTimer?.cancel();
    _pendingOffer = null;
    RandomRtcService().dispose();
    currentRoomId = null;
    partnerId = null;
    role = null;
    state.value = RandomRoomState.idle;
    remoteVideoOff.value = false;
  }

  void dispose() {
    _socketSub?.cancel();
    _cleanupFull();
  }
}
