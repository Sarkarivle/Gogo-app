import 'package:flutter/material.dart';

class PermissionOnboardingModal extends StatelessWidget {
  final bool isVideo;
  final bool isInitialOnboarding;
  final VoidCallback onAllow;

  const PermissionOnboardingModal({
    super.key,
    required this.isVideo,
    this.isInitialOnboarding = false,
    required this.onAllow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isInitialOnboarding || isVideo ? Icons.videocam_rounded : Icons.mic_rounded,
              color: Colors.orangeAccent,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isInitialOnboarding 
                ? "Calling Permissions" 
                : (isVideo ? "Video Calling Access" : "Audio Calling Access"),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isInitialOnboarding
                ? "To enable audio and video calls, we need access to your microphone and camera. This ensures high-quality communication."
                : (isVideo
                    ? "To start video calls, we need access to your camera and microphone. This ensures a smooth and secure connection."
                    : "To start audio calls, we need access to your microphone. Your privacy and security are our top priorities."),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          _buildPermissionItem(
            Icons.mic_none_rounded,
            "Microphone Access",
            "Required for others to hear your voice clearly during calls.",
          ),
          if (isInitialOnboarding || isVideo) ...[
            const SizedBox(height: 16),
            _buildPermissionItem(
              Icons.videocam_outlined,
              "Camera Access",
              "Required for video streaming during your face-to-face calls.",
            ),
          ],
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onAllow();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 0,
            ),
            child: const Text(
              "Allow Permissions",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Not Now",
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.orangeAccent, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
