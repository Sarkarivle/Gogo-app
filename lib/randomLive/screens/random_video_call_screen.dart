import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/random_rtc_service.dart';
import '../services/random_room_service.dart';
import '../services/random_socket_service.dart';
import '../../services/chat_repository.dart';
import '../../services/user_repository.dart';

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
  bool _isProcessingAction = false; // To prevent double taps
  bool _hiSent = false;

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _showExitConfirmation();
      },
      child: Scaffold(
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
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.redAccent, size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Leave Random Call?",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  "क्या आप वीडियो कॉल बंद करना चाहते हैं?",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Back to Call", style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF4B2B), Color(0xFFFF416C)]),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            if (_isProcessingAction) return;
                            if (mounted) {
                              setState(() => _isProcessingAction = true);
                              Navigator.pop(context); // Close dialog
                              RandomRoomService().endCall(this.context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text("Cut Call", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    if (_isProcessingAction) return;
    if (mounted) {
      setState(() => _isProcessingAction = true);
      Navigator.pop(context); // Close bottom sheet
      RandomRoomService().blockAndExit(context, isReport: isReport);
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
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Safe Community Info
            _buildInfoChip(),
            const SizedBox(height: 24),
            // Next & Hi Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHiButton(),
                const SizedBox(width: 12),
                _buildNextButton(),
              ],
            ),
            const SizedBox(height: 32),
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
                  onTap: () {
                    if (_isProcessingAction) return;
                    setState(() => _isProcessingAction = true);
                    RandomRoomService().endCall(context);
                  },
                ),
                _buildCompactBtn(
                  icon: Icons.switch_camera_rounded,
                  onTap: () => RandomRtcService().switchCamera(),
                ),
              ],
            ),
          ],
        ),
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
      onTap: () {
        if (_isProcessingAction) return;
        setState(() => _isProcessingAction = true);
        RandomRoomService().nextPartner(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.double_arrow_rounded, color: Colors.black, size: 20),
            SizedBox(width: 8),
            Text(
              "NEXT",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHiButton() {
    return GestureDetector(
      onTap: _hiSent ? null : _sendHiToPartner,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: _hiSent ? Colors.green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _hiSent ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_hiSent ? Icons.check_circle_rounded : Icons.waving_hand_rounded, color: _hiSent ? Colors.greenAccent : Colors.orangeAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              _hiSent ? "SENT" : "SAY HI",
              style: TextStyle(color: _hiSent ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _sendHiToPartner() async {
    final partnerId = RandomRoomService().partnerId;
    if (partnerId == null || _hiSent) return;

    final currentUser = await UserRepository().getCurrentUser();
    if (currentUser == null) return;

    ChatRepository().sendMessage(
      senderPhone: currentUser['phone'],
      receiverPhone: partnerId,
      senderName: currentUser['name'] ?? 'User',
      message: "Hi",
    );

    if (mounted) {
      setState(() => _hiSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hi sent to partner! You can find them in Inbox later."),
          backgroundColor: Colors.orangeAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
