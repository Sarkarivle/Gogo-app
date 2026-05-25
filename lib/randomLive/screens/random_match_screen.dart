import 'package:flutter/material.dart';

class RandomMatchScreen extends StatefulWidget {
  const RandomMatchScreen({super.key});

  @override
  State<RandomMatchScreen> createState() => _RandomMatchScreenState();
}

class _RandomMatchScreenState extends State<RandomMatchScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _mergeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _mergeAnimation = CurvedAnimation(
      parent: _controller, 
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0, curve: Curves.easeInOut))
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [Color(0xFF2C3E50), Color(0xFF000000)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double offset = 120 * (1 - _mergeAnimation.value);
                return ScaleTransition(
                  scale: _pulseAnimation,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow Pulse
                      if (_controller.value > 0.6)
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.pinkAccent.withValues(alpha: 0.3),
                                blurRadius: 60,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      
                      Transform.translate(
                        offset: Offset(-offset, 0),
                        child: _buildAvatar(Icons.person, Colors.blueAccent),
                      ),
                      Transform.translate(
                        offset: Offset(offset, 0),
                        child: _buildAvatar(Icons.person_pin, Colors.pinkAccent),
                      ),
                      
                      if (_controller.value > 0.5)
                        const Icon(Icons.favorite, color: Colors.amber, size: 40),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 80),
            const Text(
              "मैच मिल गया 🧡",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "वीडियो कॉल शुरू की जा रही है...",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(IconData icon, Color color) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 4),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 15)
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 55),
    );
  }
}
