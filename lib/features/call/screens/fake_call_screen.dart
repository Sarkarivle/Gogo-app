import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gogo/core/api/api_service.dart';

enum _FakeCallStage { ringing, connected, ended }

/// A simulated voice call — there's no real person on the other end, so this
/// deliberately does NOT touch CallService / WebRTCManager / CallScreen
/// (those drive real user-to-user signaling and must stay untouched). This is
/// its own small local state machine: ring (with a ringtone) for a few
/// seconds, "connect", optionally play a short pre-recorded greeting clip
/// while a call-duration clock ticks (so it reads as an actually-answered
/// call), then end — the taste-then-cut experience that nudges toward the
/// paywall or buying more credits.
///
/// Styled to match the app's light theme (unlike the real CallScreen /
/// paywall, which are deliberately dark full-screen overlays) so this reads
/// as a natural extension of the rest of the UI, not a jarring flash to
/// black.
class FakeCallScreen extends StatefulWidget {
  final String name;
  final String? photoUrl;

  /// Greeting clips to randomly pick from once "connected" — asset paths
  /// (bundled) or http(s) URLs (served from the backend, see
  /// CallGreetingService). Pass empty to skip straight from ringing to ended
  /// (no voice clip available).
  final List<String> greetingClips;

  /// Asset path for the ringback tone looped during the ringing stage.
  final String ringtoneAsset;

  /// Called once the call has finished (after the brief "Call Ended" beat)
  /// so the caller can decide where to send the user next — e.g. the
  /// credits store for creator calls, or the subscription paywall for
  /// regular free-mode calls.
  final void Function(BuildContext context) onEnded;

  const FakeCallScreen({
    super.key,
    required this.name,
    required this.onEnded,
    this.photoUrl,
    this.greetingClips = const [],
    this.ringtoneAsset = 'audio/ringtone.wav',
  });

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFFEC297B);
  static const _accent2 = Color(0xFF6A3EA1);

  _FakeCallStage _stage = _FakeCallStage.ringing;
  AudioPlayer? _ringPlayer;
  AudioPlayer? _greetingPlayer;
  Timer? _safetyTimer;
  Timer? _durationTimer;
  late final AnimationController _pulseController;

  final ValueNotifier<int> _callDuration = ValueNotifier<int>(0);
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _startSequence();
  }

  Future<void> _startSequence() async {
    _playRingtone();

    // Pick the greeting clip up front and start buffering it *while still
    // ringing* — so the moment the call "connects" the voice starts with no
    // network/decode lag, the same way a real call's audio is instant on
    // pickup.
    final hasGreeting = widget.greetingClips.isNotEmpty;
    if (hasGreeting) _prepareGreeting();

    // 1. Ringing for a couple of seconds — long enough to feel real, short
    // enough not to be tedious.
    final ringMs = 2000 + Random().nextInt(1500);
    await Future.delayed(Duration(milliseconds: ringMs));
    if (!mounted) return;

    await _stopRingtone();
    setState(() => _stage = _FakeCallStage.connected);
    _startDurationTimer();

    if (hasGreeting) {
      await _playPreparedGreeting();
      if (!mounted) return;
    } else {
      // No greeting clip available — hold briefly on "Connected" so it still
      // reads as a real pickup before cutting.
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
    }

    _endCall();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration.value++;
    });
  }

  Future<void> _playRingtone() async {
    _ringPlayer = AudioPlayer();
    try {
      await _ringPlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer!.play(AssetSource(widget.ringtoneAsset));
    } catch (_) {
      // Missing/broken ringtone asset — silently continue without sound.
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringPlayer?.stop();
    } catch (_) {}
  }

  Future<void> _prepareGreeting() async {
    _greetingPlayer = AudioPlayer();
    final clip = widget.greetingClips[Random().nextInt(widget.greetingClips.length)];
    try {
      final source = clip.startsWith('http') ? UrlSource(clip) : AssetSource(clip);
      // Loads/buffers the clip without starting playback — resume() at
      // connect-time then starts instantly.
      await _greetingPlayer!.setSource(source);
    } catch (_) {
      // If preloading fails, _playPreparedGreeting's own try/catch below
      // still handles it gracefully (falls through to the safety timer).
    }
  }

  Future<void> _playPreparedGreeting() async {
    final player = _greetingPlayer;
    if (player == null) return;
    final completer = Completer<void>();

    // Safety cap: never let the "connected" stage hang if the audio asset is
    // missing or playback fails silently on some device.
    _safetyTimer = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) completer.complete();
    });

    player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await player.resume();
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }

    return completer.future;
  }

  void _endCall() {
    if (!mounted) return;
    _stopRingtone();
    _durationTimer?.cancel();
    setState(() => _stage = _FakeCallStage.ended);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onEnded(context);
    });
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _durationTimer?.cancel();
    _ringPlayer?.dispose();
    _greetingPlayer?.dispose();
    _pulseController.dispose();
    _callDuration.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _statusWidget() {
    switch (_stage) {
      case _FakeCallStage.ringing:
        return const Text(
          'Calling...',
          style: TextStyle(color: _accent, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        );
      case _FakeCallStage.connected:
        return ValueListenableBuilder<int>(
          valueListenable: _callDuration,
          builder: (context, seconds, _) => Text(
            _formatDuration(seconds),
            style: const TextStyle(color: Color(0xFF1FA855), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        );
      case _FakeCallStage.ended:
        return const Text(
          'Call Ended',
          style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        );
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
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Voice Call',
                  style: TextStyle(color: _accent2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
              ),
              Expanded(
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
                                  width: 130 + (45 * _pulseController.value),
                                  height: 130 + (45 * _pulseController.value),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _accent.withValues(alpha: 0.15 * (1 - _pulseController.value)),
                                  ),
                                );
                              },
                            ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [_accent2, _accent]),
                              boxShadow: [
                                BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: 2),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: widget.photoUrl != null
                                  ? CachedNetworkImageProvider(ApiService.getSecureUrl(widget.photoUrl!))
                                  : null,
                              child: widget.photoUrl == null
                                  ? Icon(Icons.person, size: 60, color: Colors.grey.shade400)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.name,
                        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      _statusWidget(),
                    ],
                  ),
                ),
              ),
              _buildControls(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlIcon(_isMuted ? Icons.mic_off_rounded : Icons.mic_rounded, _isMuted, () {
            setState(() => _isMuted = !_isMuted);
          }),
          _buildControlIcon(_isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, !_isSpeakerOn, () {
            setState(() => _isSpeakerOn = !_isSpeakerOn);
          }),
          GestureDetector(
            onTap: () {
              if (_stage != _FakeCallStage.ended) _endCall();
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent,
                boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 15, spreadRadius: -3)],
              ),
              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlIcon(IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? const Color(0xFF1A1A1A) : Colors.grey.shade200,
        ),
        child: Icon(icon, color: isActive ? Colors.white : const Color(0xFF1A1A1A), size: 20),
      ),
    );
  }
}
