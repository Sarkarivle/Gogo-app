import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/permission_onboarding_modal.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  static const String _onboardingKey = 'call_permission_onboarding_shown';

  Future<void> handleChatEntryOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasShownOnboarding = prefs.getBool(_onboardingKey) ?? false;

    if (!hasShownOnboarding) {
      // Mark as shown immediately to prevent race conditions
      await prefs.setBool(_onboardingKey, true);
      
      if (!context.mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        isDismissible: false, // Force interaction for professional onboarding
        builder: (context) => PermissionOnboardingModal(
          isVideo: true, // Requesting both for the first time
          isInitialOnboarding: true,
          onAllow: () async {
            // Request both permissions together
            await [Permission.microphone, Permission.camera].request();
          },
        ),
      );
    }
  }

  Future<bool> checkAndRequestCallPermissions(BuildContext context, {required bool isVideo, bool isAutomatic = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasShownOnboarding = prefs.getBool(_onboardingKey) ?? false;

    if (!hasShownOnboarding) {
      final bool? result = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => PermissionOnboardingModal(
          isVideo: isVideo,
          isInitialOnboarding: isAutomatic,
          onAllow: () async {
            await prefs.setBool(_onboardingKey, true);
            Navigator.of(context).pop(true);
          },
        ),
      );

      if (result != true) {
        if (isAutomatic) {
           await prefs.setBool(_onboardingKey, true);
        }
        return false;
      }
    }

    // After onboarding, check actual permission status
    return await _requestPermissions(context, isVideo: isVideo);
  }

  Future<bool> _requestPermissions(BuildContext context, {required bool isVideo}) async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      if (isVideo) Permission.camera,
    ].request();

    bool allGranted = true;
    bool permanentlyDenied = false;

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          permanentlyDenied = true;
        }
      }
    });

    if (allGranted) return true;

    if (permanentlyDenied) {
      _showPermanentlyDeniedDialog(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${isVideo ? 'Camera & Microphone' : 'Microphone'} permission is required for calling."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    return false;
  }

  void _showPermanentlyDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Permissions Required", style: TextStyle(color: Colors.white)),
        content: const Text(
          "You have permanently denied camera/microphone permissions. Please enable them in app settings to use calling features.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text("OPEN SETTINGS", style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }
}
