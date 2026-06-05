import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:gogo/core/api/api_service.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;

  // Global static reference to manage single playback
  static _AudioPlayerWidgetState? _currentlyPlaying;

  const AudioPlayerWidget({super.key, required this.url, required this.isMe});
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  AudioPlayer? _player; 
  bool _isPlaying = false; 
  Duration _duration = Duration.zero; 
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _completeSub;

  void stop() async {
    if (_player != null && _isPlaying) {
      await _player!.pause();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  void initState() { 
    super.initState(); 
    // We'll initialize the player only when needed to save resources
  }

  void _initPlayer() {
    if (_player != null) return;
    _player = AudioPlayer();
    _durationSub = _player!.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }); 
    _positionSub = _player!.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }); 
    _completeSub = _player!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
        if (AudioPlayerWidget._currentlyPlaying == this) {
          AudioPlayerWidget._currentlyPlaying = null;
        }
      }
    });
  }

  @override
  void dispose() { 
    if (AudioPlayerWidget._currentlyPlaying == this) {
      AudioPlayerWidget._currentlyPlaying = null;
    }
    _durationSub?.cancel();
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose(); 
    super.dispose(); 
  }

  @override
  void didUpdateWidget(covariant AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player?.stop();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = widget.isMe ? Colors.black87 : Colors.orangeAccent.withValues(alpha: 0.8);
    final Color textColor = widget.isMe ? Colors.black54 : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              // If another audio is playing, stop it first
              if (AudioPlayerWidget._currentlyPlaying != null && 
                  AudioPlayerWidget._currentlyPlaying != this) {
                AudioPlayerWidget._currentlyPlaying!.stop();
              }

              _initPlayer(); // Initialize on first tap
              if (_isPlaying) { 
                await _player?.pause(); 
                if (mounted) {
                  setState(() => _isPlaying = false);
                  AudioPlayerWidget._currentlyPlaying = null;
                }
              } else { 
                try {
                  Source source;
                  if (widget.url.startsWith('http')) {
                    source = UrlSource(widget.url);
                  } else if (widget.url.startsWith('/api/media')) {
                    source = UrlSource(ApiService.getSecureUrl(widget.url));
                  } else {
                    source = DeviceFileSource(widget.url);
                  }
                  
                  await _player?.play(source);
                  if (mounted) {
                    setState(() => _isPlaying = true);
                    AudioPlayerWidget._currentlyPlaying = this;
                  }
                } catch (e) {
                  debugPrint("Audio Play Error: $e");
                }
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: mainColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                color: mainColor, 
                size: 28
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    width: 120, 
                    height: 4, 
                    decoration: BoxDecoration(
                      color: widget.isMe ? Colors.black.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _duration.inSeconds > 0 ? (120 * (_position.inSeconds / _duration.inSeconds)) : 0,
                    height: 4,
                    decoration: BoxDecoration(
                      color: mainColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}', 
                style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)
              ),
            ]
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final seconds = d.inSeconds % 60;
    final minutes = d.inMinutes;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class PushAnimatedWidget extends StatefulWidget {
  final Widget child;
  final bool isNew;
  final VoidCallback? onComplete;
  const PushAnimatedWidget({super.key, required this.child, this.isNew = false, this.onComplete});

  @override
  State<PushAnimatedWidget> createState() => _PushAnimatedWidgetState();
}

class _PushAnimatedWidgetState extends State<PushAnimatedWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));

    if (widget.isNew) {
      _controller.forward().then((_) {
        if (mounted) widget.onComplete?.call();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNew) return widget.child;

    return SizeTransition(
      sizeFactor: _heightFactor,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: widget.child,
        ),
      ),
    );
  }
}

class AnimatedTypingIndicator extends StatefulWidget {
  final bool isTyping;
  const AnimatedTypingIndicator({super.key, required this.isTyping});

  @override
  State<AnimatedTypingIndicator> createState() => _AnimatedTypingIndicatorState();
}

class _AnimatedTypingIndicatorState extends State<AnimatedTypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 250),
    );
    _heightFactor = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.isTyping) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTyping != oldWidget.isTyping) {
      if (widget.isTyping) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _heightFactor,
      axisAlignment: -1.0,
      child: const TypingIndicator(),
    );
  }
}

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, top: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BlinkingCircle(),
              SizedBox(width: 4),
              _BlinkingCircle(delay: 200),
              SizedBox(width: 4),
              _BlinkingCircle(delay: 400),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlinkingCircle extends StatefulWidget {
  final int delay;
  const _BlinkingCircle({this.delay = 0});
  @override
  State<_BlinkingCircle> createState() => _BlinkingCircleState();
}

class _BlinkingCircleState extends State<_BlinkingCircle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: const CircleAvatar(radius: 3, backgroundColor: Colors.white38));
  }
}
