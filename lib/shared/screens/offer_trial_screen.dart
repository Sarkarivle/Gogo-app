import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/services/analytics_service.dart';
import 'package:gogo/features/premium/providers/payment_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/repositories/payment_repository.dart';
import 'package:gogo/features/home/screens/home_screen.dart';
import 'package:gogo/features/auth/screens/profile_setup_screen.dart';
import 'package:gogo/features/premium/screens/payment_screen.dart';

class OfferTrialScreen extends StatefulWidget {
  final String offerId;
  final String name;
  final int price;
  final int duration;
  final String? googlePlayId;
  final String? googlePlaySubId;
  final String? rzpPlanId;

  const OfferTrialScreen({
    super.key,
    required this.offerId,
    required this.name,
    required this.price,
    required this.duration,
    this.googlePlayId,
    this.googlePlaySubId,
    this.rzpPlanId,
  });

  static void show(BuildContext context) {
    final offersConfig = AppConfigService().offersConfig;
    final List<dynamic> offers = offersConfig?['offers'] ?? [];
    
    if (offers.isNotEmpty) {
      final offer = offers[0];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfferTrialScreen(
            offerId: offer['id'] ?? 'monthly',
            name: offer['name'] ?? 'Premium Access',
            price: (offer['price'] as num?)?.toInt() ?? 199,
            duration: (offer['duration'] as num?)?.toInt() ?? 30,
            googlePlayId: offer['googlePlayId'],
            googlePlaySubId: offer['googlePlaySubId'],
            rzpPlanId: offer['rzpPlanId'],
          ),
        ),
      );
    } else {
      // Fallback if config is missing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OfferTrialScreen(
            offerId: 'monthly',
            name: '1 Month Premium',
            price: 199,
            duration: 30,
          ),
        ),
      );
    }
  }

  @override
  State<OfferTrialScreen> createState() => _OfferTrialScreenState();
}

class _OfferTrialScreenState extends State<OfferTrialScreen> {
  bool _isLoading = false;
  String? _currentOrderId;
  String _activeGateway = "razorpay";
  bool _isUpiEnabled = true;
  bool _isGooglePlayEnabled = true;
  bool _hasShownExitOffer = false;
  String currentArea = "आस-पास";
  Map<String, String> policyUrls = {};
  
  late ConfettiController _confettiController;
  YoutubePlayerController? _youtubeController;

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
    _youtubeController?.dispose();
    super.dispose();
  }

  void _initYoutubeVideo() {
    final trackingConfig = AppConfigService().trackingConfig;
    if (trackingConfig == null) return;
    
    String? videoId;
    final embedCode = trackingConfig['youtubeEmbedCode']?.toString();
    if (embedCode != null && embedCode.isNotEmpty) {
      if (embedCode.contains('youtube.com/embed/')) {
        try {
          final parts = embedCode.split('youtube.com/embed/')[1];
          videoId = parts.split(RegExp(r'[?&"]')).first;
        } catch (e) {
          debugPrint('Embed ID Extraction Error: $e');
        }
      } else if (!embedCode.contains('<iframe')) {
        videoId = YoutubePlayer.convertUrlToId(embedCode);
      }
    }

    if (videoId == null || videoId.isEmpty) {
      final videoUrl = trackingConfig['onboardingVideoUrl']?.toString();
      if (videoUrl != null && videoUrl.isNotEmpty) {
        videoId = YoutubePlayer.convertUrlToId(videoUrl);
      }
    }
    
    if (videoId != null && videoId.isNotEmpty) {
      if (_youtubeController == null) {
        setState(() {
          _youtubeController = YoutubePlayerController(
            initialVideoId: videoId!,
            flags: const YoutubePlayerFlags(
              autoPlay: true,
              mute: false,
              loop: true,
              disableDragSeek: true,
              enableCaption: false,
            ),
          );
        });
      }
    }
  }

  Future<void> _fetchPaymentSettings() async {
    final paymentRepo = PaymentRepository();
    final configService = AppConfigService();

    await Future.wait([
      configService.fetchReviewMode(),
      paymentRepo.fetchPaymentConfigs(),
    ]);

    _initYoutubeVideo();
    if (mounted) {
      setState(() {
        _activeGateway = paymentRepo.activeGateway;
        _isUpiEnabled = paymentRepo.isUpiEnabled;
        _isGooglePlayEnabled = paymentRepo.isGooglePlayEnabled;
      });
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link not available yet')));
      return;
    }

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch link')));
    }
  }

  Future<void> _loadUserData() async {
    final user = UserRepository().currentUser;
    if (user != null) {
      setState(() {
        currentArea = user['city']?.toString() ?? user['area']?.toString() ?? "आस-पास";
        if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
      });

      // Fetch fresh data in background
      PremiumService().syncSubscription().then((_) {
        if (mounted) {
          final freshUser = UserRepository().currentUser;
          if (freshUser != null) {
            setState(() {
              currentArea = freshUser['city']?.toString() ?? freshUser['area']?.toString() ?? "आस-पास";
              if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
            });
          }
        }
      });
    }
  }

  Future<void> _claimOffer() async {
    if (_isLoading) return;
    
    String? preferredGateway;
    if (!_isUpiEnabled && _isGooglePlayEnabled) {
      preferredGateway = 'google_play';
    }

    setState(() => _isLoading = true);
    
    try {
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";
      
      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      UserRepository().trackEvent('offer_payment_started', customId: phone);

      final response = await ApiService.post('/api/payment/create-order', {
        'phone': phone,
        'preferredGateway': preferredGateway,
        'amount': widget.price,
        'offerId': widget.rzpPlanId ?? widget.offerId,
        'googlePlayId': widget.googlePlayId,
        'googlePlaySubId': widget.googlePlaySubId,
        'duration': widget.duration,
        'isSubscription': true,
      });

      final orderData = jsonDecode(response.body);
      
      if (orderData['success'] == true) {
        final gateway = orderData['gateway']?.toString().toLowerCase() ?? _activeGateway;
        _currentOrderId = orderData['orderId'];

        final handler = PaymentService.getHandler(gateway);
        await handler.initiatePayment(
          {
            ...orderData, 
            'phone': phone, 
            'googlePlayId': widget.googlePlayId,
            'googlePlaySubId': widget.googlePlaySubId
          },
          (data) => _handlePaymentSuccess(data),
          (err) => _showError(err)
        );
      } else {
        throw orderData['message'] ?? "Order creation failed";
      }
    } catch (e) {
      _showError("Failed: $e");
    } finally {
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
        
        await AnalyticsService.logPurchase(
          widget.price.toDouble(),
          'INR',
          widget.rzpPlanId ?? widget.offerId,
        );

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
    if (msg.toLowerCase().contains('cancel') || msg.toLowerCase().contains('back')) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Payment Cancelled", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        )
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  int _getBoysCount(String area) {
    if (area == "आस-पास" || area == "unknown") return 457;
    // Consistent random number based on area name
    return 42 + (area.hashCode.abs() % 958); 
  }

  Future<void> _handleBackPress() async {
    if (_hasShownExitOffer) {
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        _showAppExitDialog();
      }
      return;
    }
    _showExitBottomSheet();
  }

  void _showExitBottomSheet() {
    setState(() => _hasShownExitOffer = true);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.pop(sheetContext);
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          } else {
            _showAppExitDialog();
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 32),
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 50),
                  const SizedBox(height: 20),
                  const Text("WAIT! DON'T MISS OUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.2)),
                  const SizedBox(height: 15),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                      children: [
                        TextSpan(text: "$currentArea ", style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                        const TextSpan(text: "mein "),
                        TextSpan(text: "${_getBoysCount(currentArea)} profiles ", style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                        const TextSpan(text: "active hain! Connect karne ke liye abhi unlock karein."),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () {
                              if (_isUpiEnabled) {
                                Navigator.pop(sheetContext);
                                Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentScreen(
                                  offerId: widget.offerId,
                                  offerName: widget.name,
                                  price: widget.price,
                                  duration: widget.duration,
                                  googlePlayId: widget.googlePlayId,
                                  googlePlaySubId: widget.googlePlaySubId,
                                  rzpPlanId: widget.rzpPlanId,
                                )));
                              }
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: Image.asset('assets/gpay_logo.png', height: 20, errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.black, size: 20)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Pay via", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
                                      const Text("GPay/UPI", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _claimOffer();
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), elevation: 0),
                              child: Text("Claim Now ₹${widget.price}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAppExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        title: const Text("Exit GoGo?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to close the app?", style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold))),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), foregroundColor: Colors.redAccent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("YES, EXIT", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    final user = UserRepository().currentUser;
    bool hasCompleted = user?['hasCompletedOnboarding'] ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Stack(
        alignment: Alignment.center,
        children: [
          AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 60),
                const SizedBox(height: 16),
                const Text("OFFER ACTIVATED", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
                const SizedBox(height: 8),
                Text("Your ${widget.name} subscription is now active.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      Navigator.pushAndRemoveUntil(
                        context, 
                        MaterialPageRoute(builder: (context) => hasCompleted ? const HomeScreen() : const ProfileSetupScreen()),
                        (route) => false
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F), Color(0xFF14070A)],
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
                                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: _handleBackPress),
                                TextButton(onPressed: () => _launchUrl('faq'), child: const Text('FAQs', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "LIMITED TIME PRICE DROP",
                              style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 15),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                              children: [
                                TextSpan(text: "${widget.name} for "),
                                TextSpan(
                                  text: "₹",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4), 
                                    decoration: TextDecoration.lineThrough, 
                                    decorationThickness: 2,
                                    fontWeight: FontWeight.w300,
                                    fontSize: 18,
                                  )
                                ),
                                TextSpan(
                                  text: "499",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4), 
                                    decoration: TextDecoration.lineThrough, 
                                    decorationThickness: 2
                                  )
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          RichText(
                            text: TextSpan(
                              children: [
                                const TextSpan(
                                  text: "₹",
                                  style: TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.w200),
                                ),
                                TextSpan(
                                  text: "${widget.price}",
                                  style: const TextStyle(color: Colors.white, fontSize: 115, fontWeight: FontWeight.w600, letterSpacing: -2),
                                ),
                              ],
                            ),
                          ),
                          Text("After trial ₹199/month", style: const TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 15),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.3),
                                    children: [
                                      TextSpan(text: "$currentArea ", style: const TextStyle(color: Colors.pinkAccent)),
                                      TextSpan(text: "mein ${_getBoysCount(currentArea)} active profiles\n"),
                                      const TextSpan(text: "aapka intezaar kar rahi hain!", style: TextStyle(color: Colors.pinkAccent)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 25),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                  ),
                                  child: Column(
                                    children: [
                                      _buildSmallBenefit(Icons.photo_library_outlined, "Photo Unlock kare"),
                                      _buildSmallBenefit(Icons.chat_bubble_outline, "Unlimited Message bheje"),
                                      _buildSmallBenefit(Icons.videocam_outlined, "Unlimited Video Call"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // Video Box
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3), width: 1.5),
                          color: Colors.black,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _youtubeController != null
                          ? YoutubePlayer(controller: _youtubeController!, showVideoProgressIndicator: true, progressIndicatorColor: Colors.pink)
                          : Stack(
                              children: [
                                Container(decoration: const BoxDecoration(image: DecorationImage(image: NetworkImage('https://images.unsplash.com/photo-1492691527719-9d1e07e534b4?q=80&w=1000&auto=format&fit=crop'), fit: BoxFit.cover))),
                                Center(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40))),
                              ],
                            ),
                      ),

                      const SizedBox(height: 10),
                      const Text("Cancel the plan anytime", style: TextStyle(color: Colors.white38, fontSize: 13)),
                      const SizedBox(height: 30),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Subscription Details",
                                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              _buildSubscriptionBullet("Trial period ke baad ye plan standard ₹199/month par auto-renew hoga."),
                              _buildSubscriptionBullet("Aap kisi bhi waqt Play Store settings se ise cancel kar sakte hain."),
                              _buildSubscriptionBullet("Success hone par premium features ka instant access mil jayega."),
                              _buildSubscriptionBullet("Your GoGo Premium subscription auto-renews at the end of the cycle. You can cancel anytime."),
                              _buildSubscriptionBullet("Premium features like high-quality video calling depend on your internet connectivity."),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                      
                      // Bottom Links
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildBottomLink("Terms & Conditions", () => _launchUrl('terms_conditions')),
                          const Text("  •  ", style: TextStyle(color: Colors.white38)),
                          _buildBottomLink("Privacy Policy", () => _launchUrl('privacy_policy')),
                          const Text("  •  ", style: TextStyle(color: Colors.white38)),
                          _buildBottomLink("Refund Policy", () => _launchUrl('refund_policy')),
                        ],
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
              // Bottom Bar
              _buildActualBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Colors.pinkAccent, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBenefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.pinkAccent, size: 18),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBottomLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white38, width: 0.8))),
        padding: const EdgeInsets.only(bottom: 1),
        child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ),
    );
  }

  Widget _buildActualBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1E1E1E), Color(0xFF1A080E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
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
                  if (_isUpiEnabled) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentScreen(
                      offerId: widget.offerId,
                      offerName: widget.name,
                      price: widget.price,
                      duration: widget.duration,
                      googlePlayId: widget.googlePlayId,
                      googlePlaySubId: widget.googlePlaySubId,
                      rzpPlanId: widget.rzpPlanId,
                    )));
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Image.asset('assets/gpay_logo.png', height: 22, errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.black, size: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Pay via", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              const Flexible(child: Text("GPay/UPI", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              if (_isUpiEnabled) const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
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
                      onPressed: _claimOffer,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), elevation: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Flexible(child: Text("Activate Now", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
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
    );
  }
}
