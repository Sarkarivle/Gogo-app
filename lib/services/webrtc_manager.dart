import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class WebRTCManager {
  static final WebRTCManager _instance = WebRTCManager._internal();
  factory WebRTCManager() => _instance;
  WebRTCManager._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;

  List<RTCIceCandidate> _remoteIceCandidates = [];
  bool _remoteDescriptionSet = false;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
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

  Future<void> initLocalStream(bool isVideo) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo ? {
        'facingMode': 'user',
        'width': {'min': 640},
        'height': {'min': 480},
        'frameRate': {'min': 30},
      } : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      debugPrint("Error getting user media: $e");
    }
  }

  Future<void> initializePeerConnection(String targetPhone) async {
    _peerConnection = await createPeerConnection(_iceServers, _config);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        SocketService().emit('ice_candidate', {
          'targetPhone': targetPhone,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint("ICE Connection State: $state");
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
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
    await _peerConnection!.setRemoteDescription(description);
    _remoteDescriptionSet = true;
    for (var candidate in _remoteIceCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteIceCandidates.clear();
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet) {
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
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
    _remoteStreamController.add(null);
    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
    _remoteDescriptionSet = false;
    _remoteIceCandidates.clear();
  }
}
