import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../services/api_service.dart';
import '../../services/app_config_service.dart';
import 'trial_onboarding_screen.dart';
import 'profile_setup_screen.dart';
import '../home_screen.dart';

class OnboardingVideoScreen extends StatefulWidget {
  const OnboardingVideoScreen({super.key});

  @override
  State<OnboardingVideoScreen> createState() => _OnboardingVideoScreenState();
}

class _OnboardingVideoScreenState extends State<OnboardingVideoScreen> {
  YoutubePlayerController? _youtubeController;
  bool _isLoading = true;
  String? _videoUrl;
  String? _videoId;

  @override
  void initState() {
    super.initState();
    _fetchVideo();
  }

  Future<void> _fetchVideo() async {
    try {
      final response = await ApiService.get('/api/user/onboarding-video');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['video'] != null) {
          _videoUrl = data['video']['videoUrl'];
          _videoId = YoutubePlayer.convertUrlToId(_videoUrl!);
          if (_videoId != null) {
            _youtubeController = YoutubePlayerController(
              initialVideoId: _videoId!,
              flags: const YoutubePlayerFlags(
                autoPlay: true,
                mute: false,
                loop: false,
                disableDragSeek: false,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching onboarding video: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  void _onSyncPressed() {
    // Navigate to next screen
    Widget nextScreen = const TrialOnboardingScreen();
    if (AppConfigService().isStandardMode) {
      nextScreen = const HomeScreen();
    }
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.pink))
              : Column(
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      "Watch This First",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        "Please watch this video to understand how GoGo works.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    const Spacer(),
                    if (_youtubeController != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.pinkAccent.withOpacity(0.3), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.pinkAccent.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: YoutubePlayer(
                          controller: _youtubeController!,
                          showVideoProgressIndicator: true,
                          progressIndicatorColor: Colors.pink,
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          "Video not available",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _onSyncPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 10,
                            shadowColor: Colors.pinkAccent.withOpacity(0.5),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "SYNC",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Icon(Icons.sync_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
