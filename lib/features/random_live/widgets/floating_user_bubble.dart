import 'dart:math';
import 'package:flutter/material.dart';

class FloatingUserBubble extends StatefulWidget {
  final String name;
  const FloatingUserBubble({super.key, required this.name});

  @override
  State<FloatingUserBubble> createState() => _FloatingUserBubbleState();
}

class _FloatingUserBubbleState extends State<FloatingUserBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _top;
  late double _left;
  late double _size;
  late Color _color;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _top = _random.nextDouble() * 600;
    _left = _random.nextDouble() * 350;
    _size = 6.0 + _random.nextDouble() * 4.0;
    
    final colors = [Colors.orangeAccent, Colors.amberAccent, Colors.grey.shade600, Colors.deepOrangeAccent];
    _color = colors[_random.nextInt(colors.length)];
    
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4 + _random.nextInt(4)),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: _top + (sin(_controller.value * 2 * pi) * 30),
          left: _left + (cos(_controller.value * 2 * pi) * 30),
          child: Opacity(
            opacity: 0.2 + (0.5 * _controller.value),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Circle
                Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: _color, blurRadius: 10, spreadRadius: 2)
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // User Name
                Text(
                  widget.name,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w500
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
