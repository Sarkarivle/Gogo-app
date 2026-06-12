import 'package:flutter/material.dart';
import 'package:gogo/features/call/providers/call_service.dart';
import 'dart:async';

class CallIndicator extends StatefulWidget {
  const CallIndicator({super.key});

  @override
  State<CallIndicator> createState() => _CallIndicatorState();
}

class _CallIndicatorState extends State<CallIndicator> {
  Timer? _timer;
  final ValueNotifier<String> _durationNotifier = ValueNotifier("00:00");
  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = CallService().stateStream.listen((state) {
      if (state == CallState.connected) {
        _startTimer();
      } else {
        _stopTimer();
      }
      if (mounted) setState(() {});
    });

    if (CallService().state == CallState.connected) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _stopTimer();
    _durationNotifier.dispose();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final startTime = CallService().startTime;
      if (startTime != null) {
        final duration = DateTime.now().difference(startTime);
        _durationNotifier.value = _formatDuration(duration);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final state = CallService().state;
    final isCallScreenActive = CallService().isCallScreenActive;
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart)),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: (state == CallState.connected && !isCallScreenActive)
          ? RepaintBoundary(
              key: const ValueKey('callIndicatorRepaintBoundary'),
              child: Container(
                key: const ValueKey('callIndicator'),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: -2),
                  ],
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => CallService().showCallScreen(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            // LEFT: Call Running Status with Icon
                            _buildCallStatusInfo(),
                            
                            const Spacer(),
                            
                            // RIGHT: Controls (Mute & End)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMuteBtn(),
                                const SizedBox(width: 8),
                                _buildEndCallBtn(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildCallStatusInfo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CallService().isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            color: Colors.greenAccent,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Call Running: ",
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                Text(
                  CallService().remoteName ?? 'User',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            ValueListenableBuilder<String>(
              valueListenable: _durationNotifier,
              builder: (context, duration, _) {
                return Text(
                  "${CallService().isVideo ? "Video" : "Voice"} • $duration",
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMuteBtn() {
    return ValueListenableBuilder<bool>(
      valueListenable: CallService().isMutedNotifier,
      builder: (context, isMuted, _) {
        return GestureDetector(
          onTap: () => CallService().toggleMute(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMuted ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: isMuted ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.white10),
            ),
            child: Icon(
              isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: isMuted ? Colors.orangeAccent : Colors.white70,
              size: 18,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEndCallBtn() {
    return GestureDetector(
      onTap: () => CallService().endCall(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.redAccent, blurRadius: 8, spreadRadius: -2)
          ]
        ),
        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}
