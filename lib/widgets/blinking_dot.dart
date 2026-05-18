import 'package:flutter/material.dart';

class BlinkingDot extends StatefulWidget {
  const BlinkingDot({super.key});
  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 6, spreadRadius: 2)],
        ),
      ),
    );
  }
}
