import 'package:flutter/material.dart';

class OrbitSearchingAnimation extends StatefulWidget {
  const OrbitSearchingAnimation({super.key});

  @override
  State<OrbitSearchingAnimation> createState() => _OrbitSearchingAnimationState();
}

class _OrbitSearchingAnimationState extends State<OrbitSearchingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Radar Pulse Waves
        ...List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              double progress = (_radarController.value + (index / 3)) % 1.0;
              return Container(
                width: 320 * progress,
                height: 320 * progress,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.8 * (1.0 - progress)),
                    width: 1.5,
                  ),
                ),
              );
            },
          );
        }),

        // Orbits with Rotating Nodes
        _buildOrbit(radius: 70, speed: 1.0, color: Colors.orangeAccent),
        _buildOrbit(radius: 110, speed: -0.6, color: Colors.amberAccent),
        _buildOrbit(radius: 150, speed: 0.4, color: Colors.orange),
        
        // Center Scanner
        _buildCenterScanner(),
      ],
    );
  }

  Widget _buildOrbit({required double radius, required double speed, required Color color}) {
    return RotationTransition(
      turns: Tween(begin: 0.0, end: speed).animate(_rotationController),
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.05), width: 1),
              ),
            ),
            Positioned(
              top: 0,
              left: radius - 6,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color, blurRadius: 10, spreadRadius: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterScanner() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Colors.orangeAccent, Colors.deepOrange],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.4), 
            blurRadius: 30, 
            spreadRadius: 2
          ),
        ],
      ),
      child: const Icon(Icons.radar_rounded, color: Colors.black, size: 36),
    );
  }
}
