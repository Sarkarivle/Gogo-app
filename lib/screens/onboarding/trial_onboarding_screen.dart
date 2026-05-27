import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import 'payment_screen.dart';
import 'profile_setup_screen.dart';
import '../home_screen.dart';

class TrialOnboardingScreen extends StatefulWidget {
  const TrialOnboardingScreen({super.key});

  @override
  State<TrialOnboardingScreen> createState() => _TrialOnboardingScreenState();
}

class _TrialOnboardingScreenState extends State<TrialOnboardingScreen> {
  String currentArea = "आस-पास";
  bool hasUsedTrial = false;
  Map<String, String> policyUrls = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchPolicies();
  }

  Future<void> _fetchPolicies() async {
    try {
      final response = await ApiService.get('/api/user/policies');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List policies = data['policies'];
          setState(() {
            for (var p in policies) {
              policyUrls[p['type']] = p['url'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching policies: $e');
    }
  }

  Future<void> _launchUrl(String type) async {
    final urlString = policyUrls[type];
    if (urlString == null || urlString.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link not available yet')),
        );
      }
      return;
    }

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch link')),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      final user = jsonDecode(userDataStr);
      final bool isPremium = user['isPremium'] ?? false;
      final bool hasCompleted = user['hasCompletedOnboarding'] ?? false;

      // Rule: If user is ALREADY premium, move them forward.
      if (isPremium) {
        if (!mounted) return;
        if (hasCompleted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileSetupScreen()));
        }
        return;
      }

      setState(() {
        // Fetch location from DB (user_data in SharedPreferences)
        currentArea = user['city']?.toString() ?? user['area']?.toString() ?? "आस-पास";
        if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
        hasUsedTrial = user['subscription']?['hasUsedTrial'] ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage('https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?q=80&w=2000&auto=format&fit=crop'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
          ),
        ),
        child: Column(
          children: [
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.26), blurRadius: 20, spreadRadius: 5)
                ]
              ),
              child: Column(
                children: [
                  // Premium Crown Icon with animation feel
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDAA520).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.workspace_premium, color: Color(0xFFDAA520), size: 40),
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w800, height: 1.3),
                      children: [
                        TextSpan(text: currentArea, style: const TextStyle(color: Color(0xFFDAA520))),
                        const TextSpan(text: " में आपके जैसे\n"),
                        const TextSpan(text: "1000+ Handsome लड़के", style: TextStyle(color: Color(0xFFDAA520))),
                        const TextSpan(text: "\nआपका इंतज़ार कर रहे हैं!"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "सिर्फ ₹1 में आज ही अपना पार्टनर ढूंढें",
                    style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    hasUsedTrial ? "Monthly Subscription" : "Special Trial Offer",
                    style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        hasUsedTrial ? "₹199" : "₹1",
                        style: const TextStyle(color: Color(0xFF1B5E20), fontSize: 90, fontWeight: FontWeight.w800, letterSpacing: -4),
                      ),
                      if (!hasUsedTrial) ...[
                        const SizedBox(width: 4),
                        const Text(
                          "only",
                          style: TextStyle(color: Colors.black38, fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      ]
                    ],
                  ),
                  if (!hasUsedTrial)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        "₹199 after trial",
                        style: TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.normal),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user, color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        "100% Secure • Cancel anytime",
                        style: TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    // Use pushReplacement if it's first-time onboarding to clean stack
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PaymentScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(
                    hasUsedTrial ? "SUBSCRIBE NOW" : "PAY NOW ₹1",
                    style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfileSetupScreen()),
                );
              },
              child: const Text(
                "I'll activate later, let me explore first",
                style: TextStyle(color: Colors.white38, fontSize: 13, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _launchUrl('terms_conditions'), 
                  child: const Text("Terms & Conditions", style: TextStyle(color: Colors.white70, fontSize: 12))
                ),
                const Text("|", style: TextStyle(color: Colors.white70)),
                TextButton(
                  onPressed: () => _launchUrl('privacy_policy'), 
                  child: const Text("Privacy Policy", style: TextStyle(color: Colors.white70, fontSize: 12))
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
