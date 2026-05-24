import 'package:flutter/material.dart';
import '../widgets/orbit_searching_animation.dart';
import '../widgets/floating_user_bubble.dart';
import '../services/random_room_service.dart';

class RandomSearchingScreen extends StatelessWidget {
  const RandomSearchingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> randomNames = ["RAVI", "DEV", "USER_92", "KUNAL", "AMAN", "SIMRAN", "PRIYA", "SAM"];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Stack(
          children: [
            // Floating Names (Glowing Circles)
            ...randomNames.map((name) => FloatingUserBubble(name: name)),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                
                // Live Radar Pulse Center
                const OrbitSearchingAnimation(),
                
                const SizedBox(height: 60),
                
                const Text(
                  "Finding Live Match",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "आपके लिए लाइव पार्टनर खोजा जा रहा है...",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                
                const Spacer(),
                
                // Premium Bottom Glass Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          "Best live match dhunda ja raha hai...",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8), 
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: TextButton(
                    onPressed: () {
                      // Small delay to prevent accidental multi-clicks during transition
                      RandomRoomService().endCall(context);
                    },
                    child: Text(
                      "CANCEL SEARCH", 
                      style: TextStyle(
                        color: Colors.redAccent.withValues(alpha: 0.7),
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      )
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
