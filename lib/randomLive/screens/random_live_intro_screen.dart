import 'package:flutter/material.dart';
import '../../services/permission_manager.dart';
import '../services/random_room_service.dart';
import 'random_searching_screen.dart';
import '../widgets/community_guidelines_modal.dart';

class RandomLiveIntroScreen extends StatelessWidget {
  const RandomLiveIntroScreen({super.key});

  void _showGuidelines(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CommunityGuidelinesModal(
        onAccept: () => _handleStartMatching(context),
      ),
    );
  }

  void _handleStartMatching(BuildContext context) async {
    final bool hasPermissions = await PermissionManager().checkAndRequestCallPermissions(
      context, 
      isVideo: true
    );

    if (hasPermissions && context.mounted) {
      RandomRoomService().init();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
      );
      RandomRoomService().startSearch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // Background Aesthetic
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orangeAccent.withValues(alpha: 0.05),
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  
                  // Central Icon
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 2),
                    ),
                    child: const Icon(Icons.bolt_rounded, size: 80, color: Colors.orangeAccent),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  const Text(
                    "Live Video Chat",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  const Text(
                    "Connect with real people instantly across the globe. 100% private & secure.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Start Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(27),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(27),
                          onTap: () => _showGuidelines(context),
                          child: const Center(
                            child: Text(
                              "START MATCHING",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.security_rounded, color: Colors.greenAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        "Safe & Encrypted Connection",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
