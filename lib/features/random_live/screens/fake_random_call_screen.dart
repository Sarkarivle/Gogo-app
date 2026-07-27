import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A simulated Random Live "partner" — there's no real stranger on the other
/// end, so this deliberately does NOT touch RandomRoomService / RandomRtcService
/// / RandomVideoCallScreen (those drive real peer signaling and must stay
/// untouched). Plays a pre-recorded clip full-screen, styled to look exactly
/// like a real random-match video call, then auto-cuts a few seconds after
/// the clip finishes — the taste-then-cut experience that nudges free-mode
/// users toward premium.
class FakeRandomCallScreen extends StatefulWidget {
  final String videoUrl;

  /// Called once the "call" has ended (clip finished + a short cut-off
  /// beat). Owns ALL navigation from here — matching how RandomRoomService
  /// drives every other exit path (partner-left, blocked, end-call) via
  /// pushAndRemoveUntil — so this screen never pops itself.
  final void Function(BuildContext context) onEnded;

  const FakeRandomCallScreen({
    super.key,
    required this.videoUrl,
    required this.onEnded,
  });

  @override
  State<FakeRandomCallScreen> createState() => _FakeRandomCallScreenState();
}

class _FakeRandomCallScreenState extends State<FakeRandomCallScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _hasEnded = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(false);
      controller.play();
      setState(() => _isReady = true);

      controller.addListener(_onVideoTick);

      // Safety cap — never let a broken/hanging clip strand the user here.
      _safetyTimer = Timer(const Duration(seconds: 25), _endCall);
    } catch (_) {
      // Clip failed to load — don't strand the user, just cut immediately.
      _endCall();
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || _hasEnded) return;
    final value = controller.value;
    if (value.isInitialized && !value.isPlaying && value.position >= value.duration && value.duration > Duration.zero) {
      // Clip finished — hold on the last frame for a beat before cutting,
      // same "ring, hear it, cut" cadence as a real dropped call.
      final holdMs = 800 + Random().nextInt(1800);
      Future.delayed(Duration(milliseconds: holdMs), _endCall);
    }
  }

  void _endCall() {
    if (_hasEnded || !mounted) return;
    _hasEnded = true;
    _safetyTimer?.cancel();
    widget.onEnded(context);
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isReady && _controller != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white54)),

            // Subtle top/bottom gradient, same as the real random-call screen,
            // so a floating end-call button reads clearly over any footage.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, Colors.transparent, Colors.black54],
                    stops: [0.0, 0.2, 0.75, 1.0],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent,
                      boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 15, spreadRadius: -3)],
                    ),
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
