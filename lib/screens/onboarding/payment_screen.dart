import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../home_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late ConfettiController _confettiController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);
    
    // Simulate real delay
    await Future.delayed(const Duration(seconds: 2));

    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = jsonDecode(prefs.getString('user_data')!);
      
      final response = await http.post(
        Uri.parse('http://72.61.170.181:5000/api/user/update-premium'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': userData['phone'],
          'isPremium': true
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await prefs.setString('user_data', jsonEncode(data['user']));
        
        setState(() => _isProcessing = false);
        _confettiController.play();
        _showSuccessPopup();
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      print(e);
    }
  }

  void _showSuccessPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Stack(
        children: [
          Center(
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, color: Colors.white, size: 45),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "AUTO PAY ENABLED",
                    style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "For GoGo Premium, an automatic recharge of ₹199 will be made from your bank every month.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black38, fontSize: 13),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("OKAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text("Payment", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
            child: const Row(children: [Icon(Icons.verified_user, color: Colors.green, size: 16), SizedBox(width: 4), Text("100% SECURE", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold))]),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.black, child: Icon(Icons.star, color: Colors.orangeAccent)),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("GoGo Premium", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Monthly Plan", style: TextStyle(color: Colors.black54, fontSize: 12)),
                    ],
                  ),
                ),
                Text("valid till ${DateTime.now().day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][DateTime.now().month-1]} ${DateTime.now().year + 1}", style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [Text("UPI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)), SizedBox(width: 8), Icon(Icons.account_balance_wallet, size: 16, color: Colors.black26)]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
              child: Row(
                children: [
                  Image.network('https://upload.wikimedia.org/wikipedia/commons/thumb/c/c7/Google_Pay_Logo.svg/1024px-Google_Pay_Logo.svg.png', width: 40),
                  const SizedBox(width: 15),
                  const Text("GPay", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isProcessing 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("PAY USING GPAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ),
          const Spacer(),
          const Text("Cancel anytime. Subscription auto-renews. Read more about", style: TextStyle(fontSize: 10, color: Colors.black38)),
          const Text("Refund and Cancellation", style: TextStyle(fontSize: 10, color: Colors.blue, decoration: TextDecoration.underline)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
