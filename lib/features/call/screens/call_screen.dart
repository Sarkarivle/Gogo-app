import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:gogo/features/call/providers/call_service.dart';
import 'package:gogo/core/network/webrtc_manager.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';

class CallScreen extends StatefulWidget {
  final String remoteName;
  final String remotePhone;
  final String? remotePhoto;
  final bool isVideo;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.remoteName,
    required this.remotePhone,
    this.remotePhoto,
    required this.isVideo,
    required this.isOutgoing,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  bool _isManualPop = false;
  Timer? _timer;
  final ValueNotifier<int> _callDuration = ValueNotifier<int>(0);
  late final String _displayId;

  late AnimationController _pulseController;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _remoteStreamSubscription;
  StreamSubscription? _localStreamSubscription;

  @override
  void initState() {
    super.initState();
    _displayId = (1000000 + Random().nextInt(8999999)).toString();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initRenderers();
    WidgetsBinding.instance.addObserver(this);
    
    _stateSubscription = CallService().stateStream.listen((state) {
      if (state == CallState.ended) {
        if (mounted && !_isManualPop) Navigator.pop(context);
      }
      if (state == CallState.connected) {
        _startTimer();
        // Attach local stream when connected for performance
        if (_localRenderer.srcObject == null && WebRTCManager().localStream != null) {
          _localRenderer.srcObject = WebRTCManager().localStream;
        }
      }
      
      // Update UI only when state changes significantly
      if (mounted) setState(() {});
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDuration.value++;
    });
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      
      _remoteStreamSubscription = WebRTCManager().remoteStreamStream.listen((stream) {
        if (mounted) {
          if (_remoteRenderer.srcObject?.id != stream?.id) {
             _remoteRenderer.srcObject = stream;
             setState(() {});
          }
        }
      });

      _localStreamSubscription = WebRTCManager().localStreamStream.listen((stream) {
        if (mounted) {
          if (_localRenderer.srcObject?.id != stream?.id) {
            // ONLY attach local stream to UI if call is CONNECTED
            if (CallService().state == CallState.connected) {
              _localRenderer.srcObject = stream;
              setState(() {});
            }
          }
        }
      });
      
      if (widget.isVideo) {
        // We don't call initLocalStream here anymore for outgoing calls to keep camera OFF.
        // It will be triggered by CallService when the receiver accepts.
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Renderer initialization error: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stateSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _localStreamSubscription?.cancel();
    _pulseController.dispose();
    _callDuration.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Re-attach stream if it was lost or ensure renderer is still working
      if (_localRenderer.srcObject == null && WebRTCManager().localStream != null) {
        _localRenderer.srcObject = WebRTCManager().localStream;
      }
      if (_remoteRenderer.srcObject == null && WebRTCManager().remoteStream != null) {
        _remoteRenderer.srcObject = WebRTCManager().remoteStream;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _isManualPop = true;
          // Fix for "call nahi cut hoti" bug: 
          // If user backs out (gesture/button), we must end the active call session.
          if (CallService().state == CallState.ringing && !widget.isOutgoing) {
            CallService().rejectCall();
          } else if (CallService().state != CallState.idle && CallService().state != CallState.ended) {
            CallService().endCall();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildRemoteView(),
            _buildDarkOverlay(),
            _buildLocalView(),
            _buildTopBar(),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkOverlay() {
    if (!widget.isVideo || CallService().state != CallState.connected) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.6),
            ],
            stops: const [0.0, 0.2, 0.8, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteView() {
    bool isRemoteVideoOff = CallService().remoteIsVideoOff;
    bool isConnected = CallService().state == CallState.connected;

    return Container(
      color: const Color(0xFF0F0F0F),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Remote Video View
          if (widget.isVideo && isConnected)
            Positioned.fill(
              child: Opacity(
                opacity: isRemoteVideoOff ? 0 : 1,
                child: RTCVideoView(
                  _remoteRenderer,
                  key: const ValueKey('remoteVideoRenderer'),
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          
          // Placeholder (shown when not connected, not video call, or camera off)
          if (!isConnected || !widget.isVideo || isRemoteVideoOff)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: (!isConnected || !widget.isVideo || isRemoteVideoOff) ? 1 : 0,
              child: _buildRemotePlaceholder(isRemoteVideoOff && isConnected),
            ),
        ],
      ),
    );
  }

  Widget _buildRemotePlaceholder(bool isCameraOff) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (CallService().state == CallState.ringing || CallService().state == CallState.connecting)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 120 + (40 * _pulseController.value),
                      height: 120 + (40 * _pulseController.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orangeAccent.withValues(alpha: 0.2 * (1 - _pulseController.value)),
                      ),
                    );
                  },
                ),
              Hero(
                tag: 'remoteAvatar',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white10,
                    backgroundImage: widget.remotePhoto != null ? CachedNetworkImageProvider(widget.remotePhoto!) : null,
                    child: widget.remotePhoto == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            "ID: $_displayId",
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          if (!isCameraOff) _buildCallStatusText(),
          if (isCameraOff)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      "Camera is Off",
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallStatusText() {
    return StreamBuilder<CallState>(
      stream: CallService().stateStream,
      initialData: CallService().state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? CallState.idle;
        String text = "";
        Color color = Colors.white70;

        switch (state) {
          case CallState.ringing:
            text = widget.isOutgoing ? 'Ringing...' : 'Incoming Call...';
            color = Colors.orangeAccent;
            break;
          case CallState.connecting:
            text = 'Connecting...';
            color = Colors.blueAccent;
            break;
          case CallState.connected:
            return ValueListenableBuilder<int>(
              valueListenable: _callDuration,
              builder: (context, seconds, _) {
                return Text(
                  _formatDuration(seconds),
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                );
              },
            );
          case CallState.ended:
            text = 'Call Ended';
            color = Colors.redAccent;
            break;
          default:
            text = "";
        }

        return Text(
          text,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        );
      }
    );
  }

  String _formatDuration(int seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildLocalView() {
    if (CallService().state != CallState.connected || !widget.isVideo) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 20,
      top: 110,
      width: 110,
      height: 160,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Local Video Preview
                RTCVideoView(
                  _localRenderer,
                  key: const ValueKey('localVideoRenderer'),
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
                
                // Local Camera Off Placeholder
                if (_isVideoOff)
                  Positioned.fill(child: _buildLocalCameraOffPlaceholder()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalCameraOffPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 30),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 50,
      left: 10,
      right: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
              onPressed: () {
                Navigator.of(context).maybePop();
              },
            ),
          ),
          if (widget.isVideo && CallService().state == CallState.connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _callDuration,
                builder: (context, seconds, _) {
                  return Text(
                    _formatDuration(seconds),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.security_outlined, color: Colors.white),
            onPressed: () => _showPremiumModerationSheet(),
          ),
        ],
      ),
    );
  }

  void _showPremiumModerationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 25),
            const Text('Safety & Moderation', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('ID: $_displayId', style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 25),
            _buildModerationTile(
              icon: Icons.report_gmailerrorred_rounded,
              title: 'Report User',
              subtitle: 'Report for harassment, scam or nudity',
              color: Colors.orangeAccent,
              onTap: () {
                Navigator.pop(context);
                _showReportOptions();
              },
            ),
            const SizedBox(height: 12),
            _buildModerationTile(
              icon: Icons.block_rounded,
              title: 'Block User',
              subtitle: 'Stop all communication with this user',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _confirmBlock();
              },
            ),
            const SizedBox(height: 30),
            SafeArea(top: false, child: const SizedBox(height: 15)), // Raised for ergonomic spacing
          ],
        ),
      ),
    );
  }

  Widget _buildModerationTile({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  void _showReportOptions() {
    final reasons = ['Harassment', 'Abusive Behavior', 'Scam / Fraud', 'Inappropriate Content', 'Underage Concern', 'Other'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text('Reason for Report', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: reasons.length,
                separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05)),
                itemBuilder: (context, index) => ListTile(
                  title: Text(reasons[index], style: const TextStyle(color: Colors.white70)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24),
                  onTap: () {
                    Navigator.pop(context);
                    final myPhone = CallService().myPhone;
                    if (myPhone != null) {
                      ChatRepository().blockUser(
                        blockerPhone: myPhone, 
                        blockedPhone: widget.remotePhone,
                        reason: reasons[index],
                        isReported: true,
                      );
                      CallService().endCall(); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Reported for ${reasons[index]}. We will investigate.'),
                          backgroundColor: Colors.blueAccent,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            SafeArea(top: false, child: const SizedBox(height: 15)), // Raised for ergonomic spacing
          ],
        ),
      ),
    );
  }

  void _confirmBlock() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Block User?', style: TextStyle(color: Colors.white)),
        content: const Text('You will no longer receive calls or messages from this user.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final myPhone = CallService().myPhone;
              if (myPhone != null) {
                ChatRepository().blockUser(blockerPhone: myPhone, blockedPhone: widget.remotePhone);
                CallService().endCall(); 
              }
            },
            child: const Text('BLOCK', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 60, // Moved up from 50 to avoid system navigation
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (CallService().state == CallState.ringing && !widget.isOutgoing)
              _buildIncomingCallControls()
            else
              _buildActiveCallControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionBtn(Icons.call_end, Colors.redAccent, "Decline", () => CallService().rejectCall()),
        _buildActionBtn(Icons.call, Colors.greenAccent, "Accept", () {
           CallService().acceptCall();
           setState(() {});
        }),
      ],
    );
  }

  Widget _buildActiveCallControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlIcon(
              _isMuted ? Icons.mic_off : Icons.mic,
              _isMuted,
              () {
                setState(() => _isMuted = !_isMuted);
                WebRTCManager().setMuted(_isMuted);
                CallService().syncState(isMuted: _isMuted, isVideoOff: _isVideoOff);
              },
            ),
            if (widget.isVideo)
              _buildControlIcon(
                _isVideoOff ? Icons.videocam_off : Icons.videocam,
                _isVideoOff,
                () {
                  setState(() => _isVideoOff = !_isVideoOff);
                  WebRTCManager().setVideoEnabled(!_isVideoOff);
                  CallService().syncState(isMuted: _isMuted, isVideoOff: _isVideoOff);
                },
              ),
            _buildControlIcon(
              _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              !_isSpeakerOn,
              () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                Helper.setSpeakerphoneOn(_isSpeakerOn);
              },
            ),
            if (widget.isVideo)
              _buildControlIcon(
                Icons.switch_camera_outlined,
                false,
                () => WebRTCManager().switchCamera(),
              ),
            _buildEndCallBtn(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlIcon(IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 20),
      ),
    );
  }

  Widget _buildEndCallBtn() {
    return GestureDetector(
      onTap: () => CallService().endCall(),
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent,
          boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 15, spreadRadius: -2)],
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)],
            ),
            child: Icon(icon, color: Colors.white, size: 35),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
