import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'random_socket_service.dart';

class RandomRtcService {
  static final RandomRtcService _instance = RandomRtcService._internal();
  factory RandomRtcService() => _instance;
  RandomRtcService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;

  final List<RTCIceCandidate> _remoteIceCandidates = [];
  bool _remoteDescriptionSet = false;
  bool isInitialized = false;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> _config = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  Future<void> initLocalStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640}, 
        'height': {'ideal': 480},
      },
    };

    try {
      if (_localStream != null) return;
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStreamController.add(_localStream);
      
      // Auto speaker on
      Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint("Error getting user media: $e");
    }
  }

  Future<void> initializePeerConnection(String roomId, String targetId) async {
    if (_peerConnection != null) return;
    
    _peerConnection = await createPeerConnection(_iceServers, _config);

    _peerConnection!.onIceCandidate = (candidate) {
      RandomSocketService().emitCandidate(roomId, targetId, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        debugPrint("[RTC] Remote stream received onTrack");
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    isInitialized = true;
  }

  Future<RTCSessionDescription> createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(description);
    _remoteDescriptionSet = true;
    for (var candidate in _remoteIceCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteIceCandidates.clear();
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet && _peerConnection != null) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      _remoteIceCandidates.add(candidate);
    }
  }

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  void switchCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void setMuted(bool muted) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
  }

  void setVideoEnabled(bool enabled) {
    if (_localStream == null) return;
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  void dispose() {
    debugPrint("[RTC] Full cleanup starting...");
    try {
      // 1. Stop local tracks
      _localStream?.getTracks().forEach((track) {
        track.stop();
        debugPrint("[RTC] Stopped local track: ${track.kind}");
      });
      _localStream?.dispose();
      _localStream = null;
      _localStreamController.add(null);

      // 2. Stop remote tracks (if any accessible)
      _remoteStream?.getTracks().forEach((track) {
        track.stop();
        debugPrint("[RTC] Stopped remote track: ${track.kind}");
      });
      _remoteStream?.dispose();
      _remoteStream = null;
      _remoteStreamController.add(null);

      // 3. Close & Dispose Peer Connection
      if (_peerConnection != null) {
        _peerConnection?.close();
        _peerConnection?.dispose();
        _peerConnection = null;
        debugPrint("[RTC] Peer connection disposed");
      }

      // 4. Reset states
      _remoteDescriptionSet = false;
      _remoteIceCandidates.clear();
      isInitialized = false;
      
    } catch (e) {
      debugPrint("[RTC] Dispose Error: $e");
    }
  }
}
