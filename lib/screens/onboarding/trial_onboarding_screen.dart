import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_screen.dart';

class TrialOnboardingScreen extends StatefulWidget {
  const TrialOnboardingScreen({super.key});

  @override
  State<TrialOnboardingScreen> createState() => _TrialOnboardingScreenState();
}

class _TrialOnboardingScreenState extends State<TrialOnboardingScreen> {
  String currentArea = "your area";

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      final user = jsonDecode(userData);
      setState(() {
        currentArea = user['area'] ?? user['city'] ?? "your area";
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
                  const Text(
                    "1 Day trial for",
                    style: TextStyle(color: Colors.black54, fontSize: 16),
                  ),
                  const Text(
                    "₹1",
                    style: TextStyle(color: Colors.green, fontSize: 48, fontWeight: FontWeight.w900),
                  ),
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PaymentScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text(
                    "PAY NOW ₹1",
                    style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
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
