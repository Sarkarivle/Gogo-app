import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  const AudioPlayerWidget({super.key, required this.url, required this.isMe});
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer(); 
  bool _isPlaying = false; 
  Duration _duration = Duration.zero; 
  Duration _position = Duration.zero;

  @override
  void initState() { 
    super.initState(); 
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }); 
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }); 
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    }); 
  }

  @override
  void dispose() { 
    _player.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, 
            color: widget.isMe ? Colors.black : Colors.orangeAccent, 
            size: 32
          ),
          onPressed: () async {
            if (_isPlaying) { 
              await _player.pause(); 
              if (mounted) setState(() => _isPlaying = false); 
            } else { 
              await _player.play(UrlSource(widget.url)); 
              if (mounted) setState(() => _isPlaying = true); 
            }
          }
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Container(
              width: 100, 
              height: 3, 
              color: Colors.white24, 
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft, 
                widthFactor: _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0, 
                child: Container(color: widget.isMe ? Colors.black : Colors.orangeAccent)
              )
            ),
            const SizedBox(height: 4),
            Text(
              '${_position.inSeconds}s / ${_duration.inSeconds}s', 
              style: TextStyle(color: widget.isMe ? Colors.black54 : Colors.white54, fontSize: 10)
            ),
          ]
        )
      ],
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
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
