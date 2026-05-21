import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:intl/intl.dart';
import 'profile_setup_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Razorpay _razorpay;
  late ConfettiController _confettiController;
  bool _isLoading = false;
  String? _currentSubscriptionId;

  Timer? _timer;
  int _secondsRemaining = 600; // 10 minutes

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _razorpay.clear();
    _confettiController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startSubscription() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    debugPrint("--- Payment Process Started ---");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr == null) throw "Local user session not found. Please login again.";
      
      final userData = jsonDecode(userDataStr);
      final phone = userData['phone']?.toString();
      if (phone == null || phone.isEmpty) throw "Phone number not found in profile.";

      debugPrint("Step 1: Requesting Order for $phone...");
      
      final url = Uri.parse('http://72.61.170.181:5000/api/payment/create-order');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw "Server timeout. Please check your internet connection.";
      });

      debugPrint("Step 2: Server Response Code: ${response.statusCode}");
      debugPrint("Step 3: Server Response Body: ${response.body}");
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        final subId = data['subscription']?['id'];
        final rzpKey = data['keyId'];
        
        if (subId == null || rzpKey == null) {
          throw "Invalid response from server: Missing Subscription ID or Key.";
        }
        
        _currentSubscriptionId = subId;
        
        debugPrint("Step 4: Data Valid. SubID: $subId, Key: $rzpKey");

        var options = {
          'key': rzpKey,
          'subscription_id': subId,
          'name': 'GoGo Premium',
          'description': '₹1 Trial Activation',
          'prefill': {
            'contact': phone,
            'email': '$phone@gogo.com'
          },
          'theme': {
            'color': '#FFD700'
          },
          'modal': {
            'confirm_close': true
          }
        };
        
        debugPrint("Step 5: Invoking Razorpay Checkout...");
        try {
          _razorpay.open(options);
          debugPrint("Step 6: Razorpay UI should be visible now.");
        } catch (rzpError) {
          throw "Razorpay SDK Error: $rzpError";
        }
      } else {
        throw data['message'] ?? "Server error: ${response.statusCode}";
      }
    } catch (e) {
      debugPrint("❌ PAYMENT INITIATION FAILED: $e");
      _showError("Failed: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isLoading = true);
    debugPrint("✅ PAYMENT SUCCESS: ${response.paymentId}");
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr == null) throw "Session lost.";
      
      final userData = jsonDecode(userDataStr);

      debugPrint("Step 7: Verifying payment with backend...");
      final verifyRes = await http.post(
        Uri.parse('http://72.61.170.181:5000/api/payment/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_subscription_id': _currentSubscriptionId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
          'phone': userData['phone']
        }),
      ).timeout(const Duration(seconds: 20));

      debugPrint("Step 8: Verification Response Body: ${verifyRes.body}");
      final data = jsonDecode(verifyRes.body);
      
      if (verifyRes.statusCode == 200 && data['success'] == true) {
        debugPrint("Step 9: Subscription fully activated!");
        await prefs.setString('user_data', jsonEncode(data['user']));
        _confettiController.play();
        _showSuccessDialog();
      } else {
        throw data['message'] ?? "Verification failed: ${verifyRes.statusCode}";
      }
    } catch (e) { 
      debugPrint("❌ VERIFICATION ERROR: $e");
      _showError("Activation Error: $e"); 
    }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() => _isLoading = false);
    _showError("Payment Cancelled");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {}

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Stack(
        alignment: Alignment.center,
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.amber, size: 60),
                const SizedBox(height: 16),
                const Text("PREMIUM ACTIVATED", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
                const SizedBox(height: 8),
                const Text("Your GoGo Premium subscription has been successfully initiated. You can now enjoy exclusive features.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileSetupScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("CONTINUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
          ConfettiWidget(confettiController: _confettiController, blastDirectionality: BlastDirectionality.explosive),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Psychology Trick: Show tomorrow's date but with a far year (2026) to look like a long-term premium deal
    String tomorrowDayMonth = DateFormat('dd MMM').format(DateTime.now().add(const Duration(days: 1)));
    String validityDate = "$tomorrowDayMonth 2026";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("GoGo Premium", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Premium Trust Header - Updated to Green for Safety Feel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: Colors.green.withOpacity(0.1), width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user, size: 14, color: Colors.green.shade400),
                const SizedBox(width: 8),
                Text("100% SECURE GOLD ACTIVATION", style: TextStyle(color: Colors.green.shade400, fontWeight: FontWeight.bold, letterSpacing: 0.8, fontSize: 10.5)),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  // Premium Crown Icon - Even Smaller
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber.withOpacity(0.15), width: 1.2),
                    ),
                    child: Icon(Icons.workspace_premium, size: 32, color: Colors.amber.shade600),
                  ),
                  const SizedBox(height: 12),
                  const Text("Activate Gold Status", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFD700), letterSpacing: -0.6)),
                  const SizedBox(height: 4),
                  Text("Join the exclusive circle of verified members", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  
                  const SizedBox(height: 16),
                  
                  // Eye-Catchy Urgent Badge with Timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.bold),
                            children: [
                              const TextSpan(text: "₹1 ऑफर सिर्फ "),
                              TextSpan(
                                text: _formatTime(_secondsRemaining),
                                style: const TextStyle(color: Colors.white, backgroundColor: Colors.red),
                              ),
                              const TextSpan(text: " मिनट के लिए मान्य"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  
                  // Premium Plan Card - More Eye Catchy
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF252525), const Color(0xFF1A1A1A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade400.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.1),
                          blurRadius: 25,
                          spreadRadius: -5,
                        )
                      ]
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Monthly Plan", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            const Text("Premium Access", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            Text("Valid till $validityDate", style: const TextStyle(color: Colors.grey, fontSize: 9)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.15))
                          ),
                          child: Text("ACTIVE", style: TextStyle(color: Colors.amber.shade600, fontWeight: FontWeight.bold, fontSize: 10)),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  
                  // GPay Logo - Clean & Smaller
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/gpay_logo.png',
                        height: 14,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 6),
                      const Text("GPay", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),

                  const SizedBox(height: 16),
                  
                  // Compact Trust Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stars, size: 10, color: Colors.amber.shade600.withOpacity(0.6)),
                      const SizedBox(width: 4),
                      Text("JOINED BY 10,000+ MEMBERS", style: TextStyle(color: Colors.grey.shade500, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSecurityMark(Icons.security_update_good, "Verified", 16),
                      _buildSecurityMark(Icons.verified_user, "Encrypted", 16),
                      _buildSecurityMark(Icons.workspace_premium, "Gold Access", 16),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Payment Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Payment Method Indicator
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/gpay_logo.png',
                        height: 18,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("GPay (UPI)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Instant & Secure Activation", style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.verified, color: Colors.blue, size: 16),
                    const SizedBox(width: 4),
                    const Text("Secured", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 24),
                
                if (_isLoading) 
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: Colors.amber))
                else
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        )
                      ]
                    ),
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _startSubscription,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700), // Vibrant Gold
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.black, size: 24),
                          SizedBox(width: 8),
                          Text("ACTIVATE NOW", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: 0.6,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.grey, fontSize: 8.5, height: 1.4),
                      children: [
                        const TextSpan(text: "Cancel anytime. Subscription auto-renews. Read more about our "),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: InkWell(
                            onTap: () {},
                            child: const Text(
                              "Refund and condition",
                              style: TextStyle(color: Colors.amber, fontSize: 8.5, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        const TextSpan(text: " for GoGo Premium users."),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldRow(String label, String value, {bool isHighlight = false, double labelFontSize = 14, double valueFontSize = 15}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: labelFontSize)),
        Text(value, style: TextStyle(color: isHighlight ? Colors.amber.shade600 : Colors.white, fontWeight: isHighlight ? FontWeight.w600 : FontWeight.bold, fontSize: valueFontSize)),
      ],
    );
  }

  Widget _buildSecurityMark(IconData icon, String label, double iconSize) {
    return Column(
      children: [
        Icon(icon, size: iconSize, color: Colors.amber.withOpacity(0.4)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 9, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
