import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/shared/screens/buy_call_credits_screen.dart';

enum _FakeCallStage { ringing, connected, ended }

/// A simulated voice call to an AI creator profile — there's no real person
/// on the other end, so this deliberately does NOT touch CallService /
/// WebRTCManager / CallScreen (those drive real user-to-user signaling and
/// must stay untouched). This is its own small local state machine: ring for
/// a few seconds, "connect", play a short pre-recorded greeting clip, then
/// end — the taste-then-cut experience that nudges toward buying more credits.
class FakeCallScreen extends StatefulWidget {
  final String name;
  final String? photoUrl;

  const FakeCallScreen({super.key, required this.name, this.photoUrl});

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> with SingleTickerProviderStateMixin {
  _FakeCallStage _stage = _FakeCallStage.ringing;
  AudioPlayer? _player;
  Timer? _safetyTimer;
  late final AnimationController _pulseController;

  static const List<String> _greetingClips = [
    'audio/call_greeting_1.mp3',
    'audio/call_greeting_2.mp3',
    'audio/call_greeting_3.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Ringing for a couple of seconds — long enough to feel real, short
    // enough not to be tedious.
    final ringMs = 2000 + Random().nextInt(1500);
    await Future.delayed(Duration(milliseconds: ringMs));
    if (!mounted) return;

    setState(() => _stage = _FakeCallStage.connected);
    await _playGreeting();
    if (!mounted) return;

    _endCall();
  }

  Future<void> _playGreeting() async {
    _player = AudioPlayer();
    final clip = _greetingClips[Random().nextInt(_greetingClips.length)];
    final completer = Completer<void>();

    // Safety cap: never let the "connected" stage hang if the audio asset is
    // missing or playback fails silently on some device.
    _safetyTimer = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) completer.complete();
    });

    _player!.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await _player!.play(AssetSource(clip));
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }

    return completer.future;
  }

  void _endCall() {
    if (!mounted) return;
    setState(() => _stage = _FakeCallStage.ended);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      // Nudge toward buying more credits right after the tease ends.
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCallCreditsScreen()));
    });
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _player?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String get _statusText {
    switch (_stage) {
      case _FakeCallStage.ringing:
        return 'Ringing...';
      case _FakeCallStage.connected:
        return 'Connected';
      case _FakeCallStage.ended:
        return 'Call Ended';
    }
  }

  Color get _statusColor {
    switch (_stage) {
      case _FakeCallStage.ringing:
        return Colors.orangeAccent;
      case _FakeCallStage.connected:
        return Colors.greenAccent;
      case _FakeCallStage.ended:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _FakeCallStage.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_stage == _FakeCallStage.ringing)
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
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.white10,
                        backgroundImage: widget.photoUrl != null
                            ? CachedNetworkImageProvider(ApiService.getSecureUrl(widget.photoUrl!))
                            : null,
                        child: widget.photoUrl == null ? const Icon(Icons.person, size: 60, color: Colors.white24) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  widget.name,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusText,
                  style: TextStyle(color: _statusColor, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  if (_stage != _FakeCallStage.ended) _endCall();
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
