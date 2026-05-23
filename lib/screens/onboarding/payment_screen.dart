import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'profile_setup_screen.dart';
import '../home_screen.dart';
import '../../services/api_service.dart';
import '../../services/premium_service.dart';
import '../../services/payment_service.dart';
import '../../services/user_repository.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late ConfettiController _confettiController;
  bool _isLoading = false;
  String? _currentOrderId;
  String _activeGateway = "razorpay";
  bool _isTrialAvailable = true;
  int _joinedCount = 51;
  String _userCity = "आस-पास";
  Map<String, String> policyUrls = {};

  Timer? _timer;
  int _secondsRemaining = 600;

  @override
  void initState() {
    super.initState();
    _joinedCount = 51 + Random().nextInt(15);
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _loadTrialStatus();
    _startTimer();
    _fetchPolicies();
    _fetchPaymentSettings();
  }

  Future<void> _fetchPaymentSettings() async {
    try {
      final response = await ApiService.get('/api/payment/settings');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _activeGateway = data['activeGateway'] ?? 'razorpay';
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
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _loadTrialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      final user = jsonDecode(userData);
      setState(() {
        _isTrialAvailable = !(user['subscription']?['hasUsedTrial'] ?? false);
        if (user['city'] != null && user['city'].toString().isNotEmpty) {
          _userCity = user['city'];
        }
      });
      UserRepository().trackEvent('trial_page_open', customId: user['phone']);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      }
      if (timer.tick % 4 == 0) {
        setState(() {
          _joinedCount += Random().nextInt(3) + 1;
          if (_joinedCount > 99) _joinedCount = 99;
        });
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
    _confettiController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startSubscription() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr == null) throw "Session lost";
      
      final userData = jsonDecode(userDataStr);
      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      UserRepository().trackEvent('payment_started', customId: phone);

      final orderData = await PaymentService.createOrder(phone);
      
      if (orderData['success'] == true) {
        final gateway = orderData['gateway']?.toString().toLowerCase() ?? 'razorpay';
        setState(() => _activeGateway = gateway);
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
          'gateway': _activeGateway,
          'orderId': _currentOrderId,
          'razorpay_payment_id': successData['paymentId'],
          'razorpay_subscription_id': successData['orderId'] ?? _currentOrderId,
          'razorpay_signature': successData['signature'],
          'merchantTransactionId': _currentOrderId,
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
    bool hasCompleted = jsonDecode(userDataStr!)['hasCompletedOnboarding'] ?? false;

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
    String tomorrowDayMonth = DateFormat('dd MMM').format(DateTime.now().add(const Duration(days: 1)));
    String validityDate = "$tomorrowDayMonth 2026";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("GoGo Premium", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.08), border: Border(bottom: BorderSide(color: Colors.green.withOpacity(0.1), width: 0.5))),
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
                children: [
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber.withOpacity(0.15), width: 1.2)),
                    child: Icon(Icons.workspace_premium, size: 32, color: Colors.amber.shade600),
                  ),
                  const SizedBox(height: 12),
                  const Text("Activate Gold Status", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFD700), letterSpacing: -0.6)),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF252525), Color(0xFF1A1A1A)]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade400.withOpacity(0.4), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_isTrialAvailable ? "Monthly Plan" : "Premium Gold", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text("Valid till $validityDate", style: const TextStyle(color: Colors.grey, fontSize: 9)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.amber.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                          child: Text("ACTIVE", style: TextStyle(color: Colors.amber.shade600, fontWeight: FontWeight.bold, fontSize: 10)),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isTrialAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.25))),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: Colors.red.shade400),
                          const SizedBox(width: 8),
                          RichText(text: TextSpan(style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.bold), children: [
                            const TextSpan(text: "₹1 ऑफर सिर्फ "),
                            TextSpan(text: _formatTime(_secondsRemaining), style: const TextStyle(color: Colors.white, backgroundColor: Colors.red)),
                            const TextSpan(text: " मिनट के लिए मान्य"),
                          ])),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber.withOpacity(0.1))),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.flash_on, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text("आपके शहर $_userCity में धूम मची है!", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text("10 km के अंदर अभी तक ", style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)), child: Text("$_joinedCount", style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900))),
                          Text(" लोग प्रीमियम बन चुके हैं", style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: const BoxDecoration(color: Color(0xFF151515), borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                      child: Image.asset(
                        _activeGateway == 'phonepe' ? 'assets/phonepe_logo.png' : 'assets/gpay_logo.png',
                        height: 18,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_activeGateway.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        const Text("Instant & Secure Activation", style: TextStyle(color: Colors.grey, fontSize: 11)),
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
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _startSubscription,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
                  child: InkWell(
                    onTap: () => _launchUrl('refund_policy'),
                    child: const Text("Read more about our Refund and condition for GoGo Premium users.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 8.5, decoration: TextDecoration.underline)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
