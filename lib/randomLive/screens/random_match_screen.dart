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
      backgroundColor: const Color(0xFF0F0F0F),
      body: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double offset = 100 * (1 - _mergeAnimation.value);
                return ScaleTransition(
                  scale: _pulseAnimation,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow Pulse (Orange)
                      if (_controller.value > 0.6)
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orangeAccent.withValues(alpha: 0.15),
                                blurRadius: 60,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      
                      Transform.translate(
                        offset: Offset(-offset, 0),
                        child: _buildAvatar(Icons.person_rounded, Colors.orangeAccent),
                      ),
                      Transform.translate(
                        offset: Offset(offset, 0),
                        child: _buildAvatar(Icons.face_retouching_natural_rounded, Colors.amberAccent),
                      ),
                      
                      if (_controller.value > 0.5)
                        const Icon(Icons.flash_on_rounded, color: Colors.orangeAccent, size: 40),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 80),
            const Text(
              "Great Match! 🧡",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "मैच मिल गया, कॉल शुरू हो रही है...",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(IconData icon, Color color) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 20)
        ],
      ),
      child: Icon(icon, color: Colors.white70, size: 50),
    );
  }
}
