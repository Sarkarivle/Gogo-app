import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_screen.dart';
import 'profile_setup_screen.dart';
import '../home_screen.dart';

class TrialOnboardingScreen extends StatefulWidget {
  const TrialOnboardingScreen({super.key});

  @override
  State<TrialOnboardingScreen> createState() => _TrialOnboardingScreenState();
}

class _TrialOnboardingScreenState extends State<TrialOnboardingScreen> {
  String currentArea = "your area";
  bool hasUsedTrial = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      final user = jsonDecode(userData);
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

      // If user is NOT premium, stay on this screen to collect payment.
      // But update UI based on whether they have used a trial before.
      setState(() {
        currentArea = user['area'] ?? user['city'] ?? "your area";
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
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
          ),
        ),
        child: Column(
          children: [
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
                      children: [
                        const TextSpan(text: "Meet with "),
                        const TextSpan(text: "1000+ Singles", style: TextStyle(color: Color(0xFFDAA520))),
                        TextSpan(text: " in $currentArea"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    hasUsedTrial ? "Monthly Subscription" : "1 Day trial for",
                    style: const TextStyle(color: Colors.black54, fontSize: 16),
                  ),
                  Text(
                    hasUsedTrial ? "₹199" : "₹1",
                    style: const TextStyle(color: Colors.green, fontSize: 48, fontWeight: FontWeight.w900),
                  ),
                  if (!hasUsedTrial)
                    const Text(
                      "₹199 after trial",
                      style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  const Text(
                    "Cancel anytime",
                    style: TextStyle(color: Colors.black38, fontSize: 14),
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
                    style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900),
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
                TextButton(onPressed: () {}, child: const Text("Terms & Conditions", style: TextStyle(color: Colors.white70, fontSize: 12))),
                const Text("|", style: TextStyle(color: Colors.white70)),
                TextButton(onPressed: () {}, child: const Text("Privacy Policy", style: TextStyle(color: Colors.white70, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
