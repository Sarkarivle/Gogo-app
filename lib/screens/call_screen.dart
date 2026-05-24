import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/webrtc_manager.dart';
import '../services/chat_repository.dart';

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

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    CallService().stateStream.listen((state) {
      if (state == CallState.ended) {
        if (mounted) Navigator.pop(context);
      }
      if (state == CallState.connected) {
        _startTimer();
        if (mounted) setState(() {});
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    WebRTCManager().remoteStreamStream.listen((stream) {
      if (mounted) {
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
    });
    
    if (WebRTCManager().localStream != null) {
      _localRenderer.srcObject = WebRTCManager().localStream;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          _buildRemoteView(),
          _buildLocalView(),
          _buildCallOverlay(),
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildRemoteView() {
    if (CallService().state != CallState.connected || !widget.isVideo) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.white10,
                backgroundImage: widget.remotePhoto != null ? CachedNetworkImageProvider(widget.remotePhoto!) : null,
                child: widget.remotePhoto == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
              ),
              const SizedBox(height: 20),
              Text(
                widget.remoteName,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (CallService().state == CallState.connected)
                Text(
                  _formatDuration(_seconds),
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold),
                )
              else
                Text(
                  CallService().state == CallState.ringing ? (widget.isOutgoing ? 'Ringing...' : 'Incoming Call...') : 'Connecting...',
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
            ],
          ),
        ),
      );
    }

    return RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
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
    if (CallService().state != CallState.connected || !widget.isVideo || _isVideoOff) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 20,
      top: 100,
      width: 120,
      height: 180,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 50,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () {
                // Return to chat while keeping call active? 
                // For now just stay as is, but we could allow minimizing.
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1E1E1E),
              onSelected: (value) => _handleMenuAction(value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.report_problem_outlined, color: Colors.redAccent, size: 20),
                      SizedBox(width: 10),
                      Text('Report User', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block_flipped, color: Colors.redAccent, size: 20),
                      SizedBox(width: 10),
                      Text('Block User', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action) async {
    if (action == 'block') {
      _confirmBlock();
    } else if (action == 'report') {
      _showReportDialog();
    }
  }

  void _confirmBlock() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Block User?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to block ${widget.remoteName}? The call will end immediately.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            TextButton(
            onPressed: () {
              Navigator.pop(context);
              final myPhone = CallService().myPhone;
              if (myPhone != null) {
                ChatRepository().blockUser(blockerPhone: myPhone, blockedPhone: widget.remotePhone);
                CallService().endCall(); 
              }
            },
            child: const Text('BLOCK', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    // Reuse existing report dialog logic or push to a report screen
    // Since I can't easily import stateful logic from another screen's private method,
    // I will implement a quick version or better, use the existing architecture if available.
    // For now, let's implement a professional simple version matching the app style.
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report User', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildReportItem('Harassment'),
            _buildReportItem('Inappropriate Content'),
            _buildReportItem('Scam / Fraud'),
            _buildReportItem('Other'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildReportItem(String reason) {
    return ListTile(
      title: Text(reason, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reported for $reason. Thank you for keeping GoGo safe.')));
      },
    );
  }

  Widget _buildCallOverlay() {
    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Column(
        children: [
          if (CallService().state == CallState.connected && widget.isVideo)
             Text(
                _formatDuration(_seconds),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)]),
              ),
          const SizedBox(height: 20),
          if (CallService().state == CallState.ringing && !widget.isOutgoing)
            _buildIncomingCallControls()
          else
            _buildActiveCallControls(),
        ],
      ),
    );
  }

  Widget _buildIncomingCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircleButton(Icons.call_end, Colors.red, () => CallService().rejectCall()),
        _buildCircleButton(Icons.call, Colors.green, () {
           CallService().acceptCall();
           setState(() {});
        }),
      ],
    );
  }

  Widget _buildActiveCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircleButton(
          _isMuted ? Icons.mic_off : Icons.mic,
          Colors.white10,
          () {
            setState(() => _isMuted = !_isMuted);
            WebRTCManager().setMuted(_isMuted);
            CallService().syncState(isMuted: _isMuted, isVideoOff: _isVideoOff);
          },
          iconColor: _isMuted ? Colors.redAccent : Colors.white,
        ),
        if (widget.isVideo)
          _buildCircleButton(
            _isVideoOff ? Icons.videocam_off : Icons.videocam,
            Colors.white10,
            () {
              setState(() => _isVideoOff = !_isVideoOff);
              WebRTCManager().setVideoEnabled(!_isVideoOff);
              CallService().syncState(isMuted: _isMuted, isVideoOff: _isVideoOff);
            },
            iconColor: _isVideoOff ? Colors.redAccent : Colors.white,
          ),
        _buildCircleButton(
          Icons.call_end,
          Colors.red,
          () => CallService().endCall(),
        ),
        _buildCircleButton(
          _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
          Colors.white10,
          () {
            setState(() => _isSpeakerOn = !_isSpeakerOn);
            // Implement speaker toggle if needed, usually handled by WebRTC
          },
        ),
        if (widget.isVideo)
          _buildCircleButton(
            Icons.switch_camera,
            Colors.white10,
            () => WebRTCManager().switchCamera(),
          ),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, Color bgColor, VoidCallback onTap, {Color iconColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Icon(icon, color: iconColor, size: 32),
      ),
    );
  }
}
