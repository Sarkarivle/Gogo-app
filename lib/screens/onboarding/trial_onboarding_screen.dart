import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import '../../services/api_service.dart';
import '../../services/payment_service.dart';
import '../../services/premium_service.dart';
import '../../services/user_repository.dart';
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
  
  bool _isLoading = false;
  String? _currentOrderId;
  String _activeGateway = "razorpay";
  bool _isUpiEnabled = true;
  bool _isGooglePlayEnabled = true;
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _loadUserData();
    _fetchPolicies();
    _fetchPaymentSettings();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _fetchPaymentSettings() async {
    try {
      final response = await ApiService.get('/api/payment/settings');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _activeGateway = data['activeGateway'] ?? 'razorpay';
            _isUpiEnabled = data['config']?['isUpiEnabled'] ?? true;
            _isGooglePlayEnabled = data['config']?['isGooglePlayEnabled'] ?? true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching payment settings: $e');
    }
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

      if (isPremium) {
        if (!mounted) return;
        if (hasCompleted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileSetupScreen()));
        }
        return;
      }

      // Set initial data from prefs
      setState(() {
        currentArea = user['city']?.toString() ?? user['area']?.toString() ?? "आस-पास";
        if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
        hasUsedTrial = user['subscription']?['hasUsedTrial'] ?? false;
      });

      // Fetch fresh data from Database to ensure location is correct
      try {
        final response = await ApiService.get('/api/user/profile/${user['phone']}');
        if (response.statusCode == 200) {
          final freshUser = jsonDecode(response.body)['user'];
          await prefs.setString('user_data', jsonEncode(freshUser));
          if (mounted) {
            setState(() {
              currentArea = freshUser['city']?.toString() ?? freshUser['area']?.toString() ?? "आस-पास";
              if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
              hasUsedTrial = freshUser['subscription']?['hasUsedTrial'] ?? false;
            });
          }
        }
      } catch (e) {
        debugPrint('Error refreshing user data: $e');
      }
    }
  }

  Future<void> _startSubscription() async {
    if (_isLoading) return;
    
    // Determine which gateway to trigger for the main button
    String? preferredGateway;
    if (!_isUpiEnabled && _isGooglePlayEnabled) {
      preferredGateway = 'google_play';
    }

    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr == null) throw "Session lost";
      
      final userData = jsonDecode(userDataStr);
      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      UserRepository().trackEvent('payment_started', customId: phone);

      // Use preferred gateway (e.g. if UPI disabled, trigger Play Store)
      final orderData = await PaymentService.createOrder(phone, gateway: preferredGateway);
      
      if (orderData['success'] == true) {
        final gateway = orderData['gateway']?.toString().toLowerCase() ?? _activeGateway;
        _currentOrderId = orderData['orderId'];

        final handler = PaymentService.getHandler(gateway);
        await handler.initiatePayment(
          {...orderData, 'phone': phone},
          (data) => _handlePaymentSuccess(data),
          (err) => _showError(err)
        );
      } else {
        throw orderData['message'] ?? "Order creation failed";
      }
    } catch (e) {
      _showError("Failed: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handlePaymentSuccess(Map<String, dynamic> successData) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr == null) throw "Session lost";
      final userData = jsonDecode(userDataStr);

      final verifyRes = await PaymentService.verifyPayment(
        userData['phone'],
        {
          'gateway': successData['gateway'] ?? _activeGateway,
          'orderId': _currentOrderId,
          'razorpay_payment_id': successData['paymentId'],
          'razorpay_subscription_id': successData['orderId'] ?? _currentOrderId,
          'razorpay_signature': successData['signature'],
          'merchantTransactionId': _currentOrderId,
          'purchaseToken': successData['purchaseToken'],
          'productId': successData['productId'],
        }
      );

      if (verifyRes['success'] == true) {
        await prefs.setString('user_data', jsonEncode(verifyRes['user']));
        await PremiumService().updatePremiumStatus(true);
        _confettiController.play();
        _showSuccessDialog();
      } else {
        throw verifyRes['message'] ?? "Verification failed";
      }
    } catch (e) {
      _showError("Activation Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  void _showSuccessDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr == null) return;
    bool hasCompleted = jsonDecode(userDataStr)['hasCompletedOnboarding'] ?? false;

    if (!mounted) return;

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
                const Text("Your GoGo Premium subscription has been successfully initiated.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      Navigator.pushAndRemoveUntil(
                        context, 
                        MaterialPageRoute(builder: (context) => hasCompleted ? const HomeScreen() : const ProfileSetupScreen()),
                        (route) => false
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A0D17), // Deep Wine/Maroon at top
              Color(0xFF0F0F0F), // Dark Black in middle
              Color(0xFF14070A), // Much more subtle Maroon glow at bottom
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    // Top Section
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              TextButton(
                                onPressed: () => _launchUrl('faq'),
                                child: const Text('FAQs', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            children: [
                              const TextSpan(text: "Start Trial for "),
                              TextSpan(
                                text: "₹99",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  decoration: TextDecoration.lineThrough,
                                  decorationThickness: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          hasUsedTrial ? "₹199" : "₹1",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 100,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -2,
                          ),
                        ),
                        if (!hasUsedTrial)
                          const Text(
                            "₹199 after trial",
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        const SizedBox(height: 15),
                        // Attraction Text (Moved up)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.3),
                              children: [
                                TextSpan(text: "$currentArea ", style: const TextStyle(color: Colors.pinkAccent)),
                                const TextSpan(text: "में "),
                                const TextSpan(text: "1000+ लड़के\n", style: TextStyle(color: Colors.pinkAccent)),
                                const TextSpan(text: "आपका इंतज़ार कर रहे है!"),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // Video Box with Border
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3), width: 1.5),
                        image: const DecorationImage(
                          image: NetworkImage('https://images.unsplash.com/photo-1492691527719-9d1e07e534b4?q=80&w=1000&auto=format&fit=crop'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                            ),
                          ),
                          const Positioned(
                            right: 15,
                            top: 15,
                            child: Icon(Icons.volume_up, color: Colors.white70, size: 20),
                          ),
                          Positioned(
                            bottom: 15,
                            left: 15,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.pink.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "LIVE PREVIEW",
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 5),
                    const Text(
                      "Cancel the plan anytime",
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),

                    const SizedBox(height: 50),
                    
                    // Added Info Text Bullet Points
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "• Your GoGo Premium subscription auto-renews at the end of the cycle. You can cancel anytime, and your access will continue until the current period expires.",
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "• Premium features like high-quality video calling and verified profile access depend on your internet connectivity and device compatibility.",
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Bottom Links
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _launchUrl('terms_conditions'),
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white38, width: 0.8)),
                            ),
                            padding: const EdgeInsets.only(bottom: 1),
                            child: const Text("Terms & Conditions", 
                              style: TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                        ),
                        const Text("  •  ", style: TextStyle(color: Colors.white38)),
                        GestureDetector(
                          onTap: () => _launchUrl('privacy_policy'),
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white38, width: 0.8)),
                            ),
                            padding: const EdgeInsets.only(bottom: 1),
                            child: const Text("Privacy Policy", 
                              style: TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                        ),
                        const Text("  •  ", style: TextStyle(color: Colors.white38)),
                        GestureDetector(
                          onTap: () => _launchUrl('refund_policy'),
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white38, width: 0.8)),
                            ),
                            padding: const EdgeInsets.only(bottom: 1),
                            child: const Text("Refund Policy", 
                              style: TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            // Bottom Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
              decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1E1E), Color(0xFF1A080E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))],
            ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const PaymentScreen()));
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Image.asset(
                                'assets/gpay_logo.png',
                                height: 22,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.black, size: 22),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Pay via", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text("GPay", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                      ),
                                      Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 50,
                        child: _isLoading 
                          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
                          : ElevatedButton(
                              onPressed: _startSubscription,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      hasUsedTrial ? "Start Now" : "Start Trial ₹1",
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_ios, size: 12),
                                ],
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
