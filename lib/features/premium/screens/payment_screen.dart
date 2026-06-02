import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gogo/features/auth/screens/profile_setup_screen.dart';
import 'package:gogo/features/home/screens/home_screen.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/premium/providers/payment_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/premium/repositories/payment_repository.dart';

class PaymentScreen extends StatefulWidget {
  final bool autoStart;
  const PaymentScreen({super.key, this.autoStart = false});

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
  bool _isUpiEnabled = true;
  bool _isGooglePlayEnabled = true;

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
    UserRepository().userNotifier.addListener(_onUserUpdated);
    
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startSubscription();
      });
    }
  }

  Future<void> _fetchPaymentSettings() async {
    final repo = PaymentRepository();
    // Use cached values from dedicated Payment Repository
    setState(() {
      _activeGateway = repo.activeGateway;
      _isUpiEnabled = repo.isUpiEnabled;
      _isGooglePlayEnabled = repo.isGooglePlayEnabled;
    });
    
    // Silent background refresh
    repo.fetchPaymentConfigs().then((_) {
      if (mounted) {
        setState(() {
          _activeGateway = repo.activeGateway;
          _isUpiEnabled = repo.isUpiEnabled;
          _isGooglePlayEnabled = repo.isGooglePlayEnabled;
        });
      }
    });
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
    final user = UserRepository().currentUser;
    if (user != null) {
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

  void _onUserUpdated() {
    if (mounted) {
      final user = UserRepository().currentUser;
      if (user != null && user['isPremium'] == true) {
        // If user became premium while this screen is open (e.g. via Socket confirmation)
        // trigger success flow if not already loading/processing
        if (!_isLoading) {
          _confettiController.play();
          _showSuccessDialog();
        }
      }
    }
  }

  @override
  void dispose() {
    UserRepository().userNotifier.removeListener(_onUserUpdated);
    _confettiController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startSubscription({String? preferredGateway}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";
      
      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      UserRepository().trackEvent('payment_started', customId: phone);

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
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";

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
        await UserRepository().updateLocalUser(verifyRes['user']);
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
    final user = UserRepository().currentUser;
    if (user == null) return;
    bool hasCompleted = user['hasCompletedOnboarding'] ?? false;

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
    String tomorrowDayMonth = DateFormat('dd MMM').format(DateTime.now().add(const Duration(days: 1)));
    String validityDate = "$tomorrowDayMonth 2026";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("Payment methods", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.08), border: Border(bottom: BorderSide(color: Colors.green.withValues(alpha: 0.1), width: 0.5))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user, size: 14, color: Colors.green.shade400),
                const SizedBox(width: 8),
                const Text("100% SECURE GOLD ACTIVATION", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, letterSpacing: 0.8, fontSize: 10.5)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  if (_isTrialAvailable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withValues(alpha: 0.25))),
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
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF252525), Color(0xFF1A1A1A)]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.4), width: 1.5),
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
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                          child: Text("ACTIVE", style: TextStyle(color: Colors.amber.shade600, fontWeight: FontWeight.bold, fontSize: 10)),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
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
                          Container(padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)), child: Text("$_joinedCount", style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800))),
                          Text(" लोग प्रीमियम बन चुके हैं", style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // UPI Apps Container
                  if (_isUpiEnabled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E1E1E), Color(0xFF151515)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("UPI Apps", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.pink.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.flash_on, color: Colors.pinkAccent.shade100, size: 12),
                                    const SizedBox(width: 4),
                                    Text("FASTEST", style: TextStyle(color: Colors.pinkAccent.shade100, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          InkWell(
                            onTap: () => _startSubscription(), // Use default server gateway
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    child: Image.asset('assets/gpay_logo.png', height: 18, errorBuilder: (c, e, s) => const Icon(Icons.payment, color: Colors.black, size: 18)),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text("GPay", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                                ],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Colors.white10, height: 1),
                          ),
                          InkWell(
                            onTap: () {}, // Future logic
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Text("Scan QR and Pay", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Google Play Container
                  if (_isGooglePlayEnabled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E1E1E), Color(0xFF151515)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Google Play", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.security, color: Colors.blue.shade300, size: 12),
                                    const SizedBox(width: 4),
                                    Text("SECURE", style: TextStyle(color: Colors.blue.shade300, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          InkWell(
                            onTap: () => _startSubscription(preferredGateway: 'google_play'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    child: Image.network(
                                      'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Google_Play_2022_icon.svg/512px-Google_Play_2022_icon.svg.png',
                                      height: 18,
                                      errorBuilder: (c, e, s) => const Icon(Icons.play_arrow_sharp, color: Colors.blue, size: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text("Google Play", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Column(
            children: [
              const Text(
                "Cancel anytime. Subscription auto-renews. Read more about",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => _launchUrl('refund_policy'),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 1), // Gap between text and underline
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white54, width: 0.8)),
                  ),
                  child: const Text(
                    "Refund & cancellation Policy",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF151515), 
                borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoading) 
                    const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: Colors.amber))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Secured by ", style: TextStyle(color: Colors.white38, fontSize: 11)),
                        const Text("India's Trusted Banks", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle, color: Colors.green.shade400, size: 14),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
