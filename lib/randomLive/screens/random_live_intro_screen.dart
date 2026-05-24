import 'package:flutter/material.dart';
import '../../services/permission_manager.dart';
import '../services/random_room_service.dart';
import 'random_searching_screen.dart';

class RandomLiveIntroScreen extends StatelessWidget {
  const RandomLiveIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a2a6c), Color(0xFFb21f1f), Color(0xFFfdbb2d)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 100, color: Colors.yellowAccent),
            const SizedBox(height: 20),
            const Text(
              "Random Live Video",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Connect with people instantly!",
              style: TextStyle(color: Colors.white70, fontSize: 18, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: () async {
                // 1. Check Camera & Mic Permissions first
                final bool hasPermissions = await PermissionManager().checkAndRequestCallPermissions(
                  context, 
                  isVideo: true
                );

                if (hasPermissions && context.mounted) {
                  // 2. If granted, proceed to matching
                  RandomRoomService().init();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RandomSearchingScreen()),
                  );
                  RandomRoomService().startSearch(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 10,
              ),
              child: const Text(
                "START MATCHING",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "100% Secure & Realtime",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontFamily: 'Inter'),
            ),
          ],
        ),
      ),
    );
  }
}
