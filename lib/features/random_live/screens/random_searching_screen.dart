import 'package:flutter/material.dart';
import '../widgets/orbit_searching_animation.dart';
import '../widgets/floating_user_bubble.dart';
import '../providers/random_room_service.dart';

class RandomSearchingScreen extends StatelessWidget {
  const RandomSearchingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> randomNames = ["RAHUL", "AMIT", "SANDEEP", "VIKRAM", "ANKIT", "SUMIT", "ROHIT", "DEEPAK"];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Floating Names (Branded Colors)
            ...randomNames.map((name) => FloatingUserBubble(name: name)),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                
                // Live Radar Pulse Center (Branded)
                const OrbitSearchingAnimation(),
                
                const SizedBox(height: 60),
                
                const Text(
                  "Finding Your Match",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "आपके लिए लाइव पार्टनर खोजा जा रहा है...",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                
                const Spacer(),
                
                // Premium Bottom Glass Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          "Best live match dhunda ja raha hai...",
                          style: TextStyle(
                            color: Colors.white38, 
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: TextButton(
                    onPressed: () {
                      RandomRoomService().endCall(context);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent.withValues(alpha: 0.5),
                    ),
                    child: const Text(
                      "CANCEL SEARCH", 
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 13,
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
