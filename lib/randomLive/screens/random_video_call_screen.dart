import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/random_rtc_service.dart';
import '../services/random_room_service.dart';
import '../services/random_socket_service.dart';
import '../../services/chat_repository.dart';
import '../../services/socket_service.dart';

class RandomVideoCallScreen extends StatefulWidget {
  const RandomVideoCallScreen({super.key});

  @override
  State<RandomVideoCallScreen> createState() => _RandomVideoCallScreenState();
}

class _RandomVideoCallScreenState extends State<RandomVideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    try {
      // 1. Initialize renderers immediately
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      if (!mounted) return;

      // 2. Listen for stream events
      RandomRtcService().localStreamStream.listen((stream) {
        if (mounted) setState(() => _localRenderer.srcObject = stream);
      });

      RandomRtcService().remoteStreamStream.listen((stream) {
        if (mounted) {
          debugPrint("[RTC] Remote stream attached to renderer");
          setState(() => _remoteRenderer.srcObject = stream);
        }
      });
      
      // 3. Immediate attach if streams already exist (Safety)
      if (RandomRtcService().localStream != null) {
        _localRenderer.srcObject = RandomRtcService().localStream;
      }
      if (RandomRtcService().remoteStream != null) {
        _remoteRenderer.srcObject = RandomRtcService().remoteStream;
      }

      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("[CallScreen] Init Error: $e");
    }
  }

  @override
  void dispose() {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Remote Fullscreen Video
          _buildRemoteVideoView(),

          // 2. Dark Gradient Overlays (Top/Bottom)
          _buildGradientOverlays(),

          // 3. Top Menu (Block/Report)
          _buildTopMenu(),

          // 4. Local Preview (Floating)
          _buildLocalPreview(),

          // 5. Bottom Controls
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildRemoteVideoView() {
    return ValueListenableBuilder<bool>(
      valueListenable: RandomRoomService().remoteVideoOff,
      builder: (context, isOff, _) {
        if (isOff) {
          return _buildRemoteCameraOffPlaceholder();
        }
        
        return _isInitialized 
          ? RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2));
      },
    );
  }

  Widget _buildRemoteCameraOffPlaceholder() {
    final String partnerId = RandomRoomService().partnerId ?? "User";
    final String maskedName = partnerId.length > 4 
        ? "USER_${partnerId.substring(partnerId.length - 4)}" 
        : "USER_$partnerId";

    return Container(
      color: const Color(0xFF121212),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(Icons.person, color: Colors.white24, size: 60),
          ),
          const SizedBox(height: 20),
          Text(
            maskedName,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(
                "Camera is Off",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopMenu() {
    return Positioned(
      top: 50,
      left: 20,
      child: GestureDetector(
        onTap: _showModerationOptions,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(color: Colors.white24, width: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  void _showModerationOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            _buildModerationAction(
              icon: Icons.block_rounded,
              title: "Block User",
              color: Colors.redAccent,
              onTap: () => _handleModerationAction(isReport: false),
            ),
            _buildModerationAction(
              icon: Icons.report_problem_rounded,
              title: "Block & Report",
              color: Colors.orangeAccent,
              onTap: () => _handleModerationAction(isReport: true),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            const SafeArea(child: SizedBox(height: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildModerationAction({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  void _handleModerationAction({required bool isReport}) async {
    final String? myPhone = SocketService().currentUserPhone;
    final String? pId = RandomRoomService().partnerId;
    
    if (myPhone != null && pId != null) {
      ChatRepository().blockUser(
        blockerPhone: myPhone,
        blockedPhone: pId,
        isReported: isReport,
        reason: isReport ? "Random Call Report" : "No reason"
      );
      if (mounted) {
        Navigator.pop(context);
        RandomRoomService().nextPartner(context);
      }
    }
  }

  Widget _buildLocalPreview() {
    return Positioned(
      top: 60,
      right: 20,
      child: Container(
        width: 110,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15)
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _isInitialized 
            ? RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: true)
            : Container(color: Colors.black),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Safe Community Info
          _buildInfoChip(),
          const SizedBox(height: 20),
          // Next Button
          _buildNextButton(),
          const SizedBox(height: 35),
          // Compact Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactBtn(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                active: _isMuted,
                onTap: () {
                  setState(() => _isMuted = !_isMuted);
                  RandomRtcService().setMuted(_isMuted);
                },
              ),
              _buildCompactBtn(
                icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                active: _isVideoOff,
                onTap: () {
                  setState(() => _isVideoOff = !_isVideoOff);
                  RandomRtcService().setVideoEnabled(!_isVideoOff);
                  // Sync call state to remote
                  final rId = RandomRoomService().currentRoomId;
                  final pId = RandomRoomService().partnerId;
                  if (rId != null && pId != null) {
                    RandomSocketService().syncCallState(rId, pId, _isVideoOff);
                  }
                },
              ),
              _buildCompactBtn(
                icon: Icons.call_end,
                isEnd: true,
                onTap: () => RandomRoomService().endCall(context),
              ),
              _buildCompactBtn(
                icon: Icons.switch_camera_rounded,
                onTap: () => RandomRtcService().switchCamera(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            "सुरक्षित समुदाय के लिए सम्मानजनक व्यवहार करें",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return GestureDetector(
      onTap: () => RandomRoomService().nextPartner(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: const Color(0xFF8E2DE2).withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.double_arrow_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              "NEXT PARTNER",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactBtn({required IconData icon, bool active = false, bool isEnd = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isEnd ? Colors.redAccent : (active ? Colors.white : Colors.white.withValues(alpha: 0.1)),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10, width: 0.5),
            ),
            child: Icon(icon, color: isEnd ? Colors.white : (active ? Colors.black : Colors.white), size: 26),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlays() {
    return Column(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 300,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}
