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

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;

  List<RTCIceCandidate> _remoteIceCandidates = [];
  bool _remoteDescriptionSet = false;

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

  Future<void> initLocalStream(bool isVideo) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo ? {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30, 'max': 30},
      } : false,
    };

    try {
      if (_localStream != null) {
        // Optimization: if we already have a stream and just need to enable/disable tracks, 
        // don't recreate the whole stream to prevent flickering.
        final videoTracks = _localStream!.getVideoTracks();
        if (isVideo && videoTracks.isNotEmpty) {
           videoTracks[0].enabled = true;
           return;
        } else if (!isVideo && videoTracks.isNotEmpty) {
           videoTracks[0].enabled = false;
           // We might still want to keep the stream alive
        }
        
        // If we really need a new stream (e.g. switching from audio-only to video)
        // only then we proceed to dispose.
        if (isVideo && videoTracks.isEmpty) {
           _localStream!.getTracks().forEach((track) => track.stop());
           await _localStream!.dispose();
           _localStream = null;
        } else {
          return; // Already have what we need
        }
      }

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStreamController.add(_localStream);
    } catch (e) {
      debugPrint("Error getting user media: $e");
    }
  }

  Future<void> initializePeerConnection(String targetPhone) async {
    if (_peerConnection != null) return;
    
    _peerConnection = await createPeerConnection(_iceServers, _config);

    _peerConnection!.onIceCandidate = (candidate) {
      SocketService().emit('ice_candidate', {
        'targetPhone': targetPhone,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
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

    // Apply bitrate constraints after a short delay to ensure tracks are added
    Future.delayed(const Duration(milliseconds: 500), () => _setBitrate());
  }

  void _setBitrate() async {
    if (_peerConnection == null) return;
    
    final senders = await _peerConnection!.getSenders();
    for (var sender in senders) {
      final track = sender.track;
      if (track != null && track.kind == 'video') {
        final parameters = sender.parameters;
        if (parameters.encodings != null && parameters.encodings!.isNotEmpty) {
          parameters.encodings![0].maxBitrate = 1500 * 1000; // 1.5 Mbps for 720p
          await sender.setParameters(parameters);
          debugPrint("✅ Video bitrate capped at 1.5Mbps for stability");
        }
      }
    }
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
    _localStreamController.add(null);
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
