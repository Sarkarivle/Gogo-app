import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  /// Whichever chat/profile the user was on when they hit the paywall (e.g.
  /// mid-call tease, blocked message, locked photo) — used to personalize
  /// the headline ("Call {creatorName} anytime") instead of a generic pitch.
  /// Both null falls back to generic copy.
  final String? creatorName;
  final String? creatorPhotoUrl;

  /// True when the paywall was triggered by a private-chat feature (Go
  /// Private banner, locked photo/audio message) rather than the call
  /// tease — shows the creator photo blurred with a lock overlay instead of
  /// a clear photo, since the content itself is what's being sold.
  final bool isPrivateChat;

  const OfferTrialScreen({
    super.key,
    required this.offerId,
    required this.name,
    required this.price,
    required this.duration,
    this.googlePlayId,
    this.googlePlaySubId,
    this.rzpPlanId,
    this.creatorName,
    this.creatorPhotoUrl,
    this.isPrivateChat = false,
  });

  static void show(
    BuildContext context, {
    String? creatorName,
    String? creatorPhotoUrl,
    bool isPrivateChat = false,
  }) async {
    final configService = AppConfigService();

    // If config is missing, fetch it first before showing screen
    if (configService.offersConfig == null) {
      await configService.fetchReviewMode(forceRefresh: true);
    }

    if (!context.mounted) return;

    final offersConfig = configService.offersConfig;
    final List<dynamic> offers = offersConfig?['offers'] ?? [];

    if (offers.isNotEmpty) {
      final offer = offers.length > 1
          ? offers[1]
          : offers[0]; // Prefer middle plan (Monthly)
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
            creatorName: creatorName,
            creatorPhotoUrl: creatorPhotoUrl,
            isPrivateChat: isPrivateChat,
          ),
        ),
      );
    } else {
      // Fallback only if server is unreachable
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfferTrialScreen(
            offerId: 'monthly',
            name: '1 Month Premium',
            price: 199,
            duration: 30,
            creatorName: creatorName,
            creatorPhotoUrl: creatorPhotoUrl,
            isPrivateChat: isPrivateChat,
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
  bool _hasShownExitOffer = false;
  String currentArea = "आस-पास";
  Map<String, String> policyUrls = {};

  List<Map<String, dynamic>> _plans = [];
  int _selectedPlanIndex = 1; // Default to Monthly (199)

  final PageController _testimonialController = PageController(viewportFraction: 1);
  int _testimonialPage = 0;

  static const List<Map<String, String>> _testimonials = [
    {
      'name': 'Santosh Yadav',
      'place': 'Patna · Last week',
      'quote': 'मुझे लगा था बस chat app है लेकिन प्राइवेट मोड और फोटोज 📸 ने सोच बदल दी.. सच में worth it है 💯',
      'likes': '245',
    },
    {
      'name': 'Rahul Verma',
      'place': 'Delhi · 3 days ago',
      'quote': 'Voice call feature best hai, bilkul real jaisa lagta hai. Paisa vasool!',
      'likes': '189',
    },
    {
      'name': 'Ankit Sharma',
      'place': 'Lucknow · 2 weeks ago',
      'quote': 'Privacy ka dhyan rakha gaya hai, screenshots block hone se bharosa badh gaya.',
      'likes': '312',
    },
    {
      'name': 'Vikas Singh',
      'place': 'Kanpur · 5 days ago',
      'quote': 'Pehle free mein try kiya, phir premium le liya — koi regret nahi hai.',
      'likes': '156',
    },
    {
      'name': 'Deepak Kumar',
      'place': 'Jaipur · 1 week ago',
      'quote': 'Exclusive photos aur unlimited messages ka combo sabse best deal laga mujhe.',
      'likes': '278',
    },
    {
      'name': 'Amit Yadav',
      'place': 'Varanasi · 4 days ago',
      'quote': 'App smooth chalta hai aur support bhi turant reply karta hai. Recommended!',
      'likes': '203',
    },
  ];

  late ConfettiController _confettiController;
  YoutubePlayerController? _youtubeController;

  // Urgency countdown shown near the bottom bar ("offer ends in").
  Timer? _countdownTimer;
  Duration _offerCountdown = const Duration(minutes: 23);

  @override
  void initState() {
    super.initState();
    // 1. Load initial plans from existing config
    _initPlans();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _offerCountdown = _offerCountdown.inSeconds > 0
            ? _offerCountdown - const Duration(seconds: 1)
            : const Duration(minutes: 23);
      });
    });

    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _loadUserData();
    _fetchPolicies();

    // 2. Fetch fresh config and update UI
    _fetchPaymentSettings();
  }

  void _initPlans() {
    final offersConfig = AppConfigService().offersConfig;
    final List<dynamic> configOffers = offersConfig?['offers'] ?? [];

    debugPrint(
        'DEBUG: Initializing Plans from Config: ${configOffers.length} items found');

    if (configOffers.isNotEmpty) {
      _plans = configOffers.map((e) {
        final map = Map<String, dynamic>.from(e);
        final price = (map['price'] as num?)?.toInt() ?? 0;

        // Use backend provided original price if exists, otherwise dynamic calculation
        if (map['originalPrice'] == null) {
          if (price == 199) {
            map['originalPrice'] = 499;
          } else if (price == 99 || price == 100) {
            map['originalPrice'] = 220;
          } else if (price == 19) {
            map['originalPrice'] = 41;
          } else if (price == 499) {
            map['originalPrice'] = 999;
          } else if (price == 1) {
            map['originalPrice'] = 199;
          } else {
            map['originalPrice'] = (price * 2.2).toInt();
          }
        }

        return map;
      }).toList();
    } else {
      // Default fallback
      _plans = [
        {
          'id': 'weekly',
          'name': '7 Days',
          'price': 99,
          'originalPrice': 220,
          'duration': 7,
          'googlePlayId': 'gogo_weekly_99',
          'rzpPlanId': 'plan_weekly'
        },
        {
          'id': 'monthly',
          'name': '1 Month ',
          'price': 199,
          'originalPrice': 499,
          'duration': 30,
          'googlePlayId': 'gogo_monthly_199',
          'rzpPlanId': 'plan_monthly'
        },
        {
          'id': 'quarterly',
          'name': '3 Months',
          'price': 499,
          'originalPrice': 999,
          'duration': 90,
          'googlePlayId': 'gogo_quarterly_499',
          'rzpPlanId': 'plan_quarterly'
        },
      ];
    }

    // Always default to Middle plan if available
    _selectedPlanIndex = (_plans.length > 1) ? 1 : 0;

    // Sync with widget price if needed
    for (int i = 0; i < _plans.length; i++) {
      if (_plans[i]['price'] == widget.price) {
        _selectedPlanIndex = i;
        break;
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _confettiController.dispose();
    _youtubeController?.dispose();
    _testimonialController.dispose();
    super.dispose();
  }

  String get _formattedCountdown {
    final m = _offerCountdown.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _offerCountdown.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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

    // Show loading if plans are currently empty (fallback used)
    if (_plans.isEmpty || _plans[0]['price'] == 99) {
      setState(() => _isLoading = true);
    }

    try {
      await Future.wait([
        configService.fetchReviewMode(forceRefresh: true),
        paymentRepo.fetchPaymentConfigs(forceRefresh: true),
      ]);
    } catch (e) {
      debugPrint('Config Fetch Error: $e');
    }

    _initYoutubeVideo();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _activeGateway = paymentRepo.activeGateway;
        _isUpiEnabled = paymentRepo.isUpiEnabled;
        _initPlans(); // RE-SYNC PLANS FROM FETCHED CONFIG
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link not available yet')));
      }
      return;
    }

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch link')));
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = UserRepository().currentUser;
    if (user != null) {
      setState(() {
        currentArea =
            user['city']?.toString() ?? user['area']?.toString() ?? "आस-पास";
        if (currentArea.toLowerCase() == "unknown") currentArea = "आस-पास";
      });

      // Fetch fresh data in background
      PremiumService().syncSubscription().then((_) {
        if (mounted) {
          final freshUser = UserRepository().currentUser;
          if (freshUser != null) {
            setState(() {
              currentArea = freshUser['city']?.toString() ??
                  freshUser['area']?.toString() ??
                  "आस-पास";
              if (currentArea.toLowerCase() == "unknown") {
                currentArea = "आस-पास";
              }
            });
          }
        }
      });
    }
  }

  Future<void> _claimOffer() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";

      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      UserRepository().trackEvent('offer_payment_started', customId: phone);

      final selectedPlan = _plans[_selectedPlanIndex];

      final orderData = await PaymentService.createOrder(
        phone,
        gateway: _isUpiEnabled ? 'razorpay' : 'google_play',
        amount: selectedPlan['price'],
        offerId: selectedPlan['rzpPlanId'] ?? selectedPlan['id'],
        googlePlayId: selectedPlan['googlePlayId'],
        googlePlaySubId: selectedPlan['googlePlaySubId'],
        duration: selectedPlan['duration'],
        isSubscription: false,
      );

      if (orderData['success'] == true) {
        final gateway =
            orderData['gateway']?.toString().toLowerCase() ?? _activeGateway;
        _currentOrderId = orderData['orderId'];

        final handler = PaymentService.getHandler(gateway);
        await handler.initiatePayment({
          ...orderData,
          'phone': phone,
          if (selectedPlan['googlePlayId']?.toString().trim().isNotEmpty ==
              true)
            'googlePlayId': selectedPlan['googlePlayId'],
          if (selectedPlan['googlePlaySubId']?.toString().trim().isNotEmpty ==
              true)
            'googlePlaySubId': selectedPlan['googlePlaySubId']
        }, (data) => _handlePaymentSuccess(data), (err) => _showError(err));
      } else {
        throw orderData['message']?.toString() ?? "Order creation failed";
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

      final verifyRes = await PaymentService.verifyPayment(userData['phone'], {
        ...successData,
        'gateway': successData['gateway'] ?? _activeGateway,
        'orderId': _currentOrderId,
        'merchantTransactionId': _currentOrderId,
      });

      if (verifyRes['success'] == true) {
        await UserRepository().updateLocalUser(verifyRes['user']);
        await PremiumService().updatePremiumStatus(true);

        final selectedPlan = _plans[_selectedPlanIndex];
        await AnalyticsService.logPurchase(
          (selectedPlan['price'] as num).toDouble(),
          'INR',
          selectedPlan['rzpPlanId'] ?? selectedPlan['id'],
          eventId:
              'purchase_${successData['paymentId'] ?? successData['orderId'] ?? _currentOrderId ?? selectedPlan['rzpPlanId'] ?? selectedPlan['id']}',
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
    if (msg.toLowerCase().contains('cancel') ||
        msg.toLowerCase().contains('back')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Payment Cancelled",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
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
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 32),
                  const Icon(Icons.stars_rounded,
                      color: Colors.amber, size: 50),
                  const SizedBox(height: 20),
                  const Text("WAIT! DON'T MISS OUT",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 15),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15, height: 1.5),
                      children: [
                        TextSpan(
                            text: "$currentArea ",
                            style: const TextStyle(
                                color: Colors.pinkAccent,
                                fontWeight: FontWeight.bold)),
                        const TextSpan(text: "mein "),
                        TextSpan(
                            text: "${_getBoysCount(currentArea)} profiles ",
                            style: const TextStyle(
                                color: Colors.pinkAccent,
                                fontWeight: FontWeight.bold)),
                        const TextSpan(
                            text:
                                "active hain! Connect karne ke liye abhi unlock karein."),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        if (_isUpiEnabled) ...[
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => PaymentScreen(
                                              offerId: widget.offerId,
                                              offerName: widget.name,
                                              price: widget.price,
                                              duration: widget.duration,
                                              googlePlayId: widget.googlePlayId,
                                              googlePlaySubId:
                                                  widget.googlePlaySubId,
                                              rzpPlanId: widget.rzpPlanId,
                                            )));
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle),
                                    child: Image.asset('assets/gpay_logo.png',
                                        height: 20,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(Icons.payment,
                                                    color: Colors.black,
                                                    size: 20)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text("Pay via",
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500)),
                                        const Text("GPay/UPI",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _claimOffer();
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.pink,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25)),
                                  elevation: 0),
                              child: Text(
                                  "Claim Now ₹${_plans[_selectedPlanIndex]['price']}",
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        title: const Text("Exit Lulu?",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to close the app?",
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL",
                  style: TextStyle(
                      color: Colors.white38, fontWeight: FontWeight.bold))),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text("YES, EXIT",
                style: TextStyle(fontWeight: FontWeight.bold)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 60),
                const SizedBox(height: 16),
                const Text("OFFER ACTIVATED",
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.black)),
                const SizedBox(height: 8),
                Text(
                    "Your ${_plans[_selectedPlanIndex]['name']} subscription is now active.",
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => hasCompleted
                                  ? const HomeScreen()
                                  : const ProfileSetupScreen()),
                          (route) => false);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text("CONTINUE",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
              ],
            ),
          ),
          ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive),
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
                                IconButton(
                                    icon: const Icon(Icons.arrow_back,
                                        color: Colors.white),
                                    onPressed: _handleBackPress),
                                GestureDetector(
                                  onTap: () => _launchUrl('faq'),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                        color: Colors.black26,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.volume_up_rounded,
                                        color: Colors.white70, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildCreatorHero(),
                          const SizedBox(height: 24),
                          _buildFeatureList(),
                          const SizedBox(height: 24),
                          _buildSafetyCard(),
                          const SizedBox(height: 20),
                          _buildTestimonialCard(),
                          const SizedBox(height: 14),
                          _buildDots(),
                          const SizedBox(height: 24),
                          _buildJoinPill(),
                          const SizedBox(height: 30),
                          const Text("CHOOSE YOUR PREMIUM PLAN",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: List.generate(_plans.length,
                                  (index) => _buildPlanOption(index)),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _selectedPlanIndex == 1
                                ? "Recommended for you"
                                : "Unlock all premium features",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.pinkAccent.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildBottomLink("Terms & Conditions",
                                  () => _launchUrl('terms_conditions')),
                              const Text("  •  ",
                                  style: TextStyle(color: Colors.white38)),
                              _buildBottomLink("Privacy Policy",
                                  () => _launchUrl('privacy_policy')),
                              const Text("  •  ",
                                  style: TextStyle(color: Colors.white38)),
                              _buildBottomLink(
                                  "Refund Policy", () => _launchUrl('refund_policy')),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Sticky urgency timer, stays pinned above the bottom pay bar.
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer_outlined,
                        color: Colors.pinkAccent, size: 12),
                    const SizedBox(width: 4),
                    Text("$_formattedCountdown offer ends",
                        style: const TextStyle(
                            color: Colors.pinkAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                    const Text("  ·  ",
                        style: TextStyle(color: Colors.white24, fontSize: 10)),
                    Icon(Icons.shield_outlined,
                        color: Colors.green.withValues(alpha: 0.5),
                        size: 12),
                    const SizedBox(width: 4),
                    const Text("Secure UPI",
                        style: TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
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

  Widget _buildPlanOption(int index) {
    final plan = _plans[index];
    final isSelected = _selectedPlanIndex == index;
    final bool isBestValue = index == 1; // 199 plan

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlanIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.symmetric(
              horizontal: 4, vertical: isBestValue ? 0 : 8),
          padding: EdgeInsets.symmetric(vertical: isBestValue ? 24 : 16),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.pinkAccent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.pinkAccent
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.pinkAccent.withValues(alpha: 0.3),
                        blurRadius: 8)
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBestValue)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.pinkAccent,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text("POPULAR",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                )
              else
                const SizedBox(height: 18),
              Text(
                plan['name'],
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (plan['originalPrice'] != null)
                Text(
                  "₹${plan['originalPrice']}",
                  style: TextStyle(
                    color: isSelected ? Colors.white54 : Colors.white38,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                    decorationColor:
                        isSelected ? Colors.pinkAccent : Colors.white38,
                  ),
                ),
              Text(
                "₹${plan['price']}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _durationLabel {
    final duration = _plans.isNotEmpty
        ? (_plans[_selectedPlanIndex]['duration'] as num?)?.toInt() ?? widget.duration
        : widget.duration;
    if (duration == 30) return "Poore mahine ke liye";
    if (duration == 7) return "1 hafte ke liye";
    if (duration == 90) return "3 mahine ke liye";
    return "$duration din ke liye";
  }

  int get _discountPercent {
    if (_plans.isEmpty) return 50;
    final plan = _plans[_selectedPlanIndex];
    final price = (plan['price'] as num?)?.toDouble() ?? 0;
    final original = (plan['originalPrice'] as num?)?.toDouble() ?? 0;
    if (original <= 0 || price >= original) return 0;
    return (((original - price) / original) * 100).round();
  }

  Widget _buildCreatorHero() {
    final name = widget.creatorName;
    final isPrivate = widget.isPrivateChat;
    return Column(
      children: [
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
                colors: [Color(0xFF6A3EA1), Color(0xFFEC297B)]),
            boxShadow: [
              BoxShadow(
                  color: Colors.pinkAccent.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.creatorPhotoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: ApiService.getSecureUrl(widget.creatorPhotoUrl!),
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            _heroPhotoPlaceholder(),
                      )
                    : _heroPhotoPlaceholder(),
                if (isPrivate) ...[
                  // Private-chat content is being sold, so tease it blurred
                  // instead of showing the photo clearly.
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(color: Colors.black.withValues(alpha: 0.25)),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.black45, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          isPrivate
              ? (name != null ? "Unlock Private Chat with $name" : "Unlock Private Chat")
              : (name != null ? "Call $name anytime" : "Unlock Full Access Now"),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.amber,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2),
        ),
        const SizedBox(height: 6),
        Text(
          isPrivate
              ? (name != null
                  ? "$name ke saath romantic chats & exclusive photos"
                  : "Romantic chats & exclusive photos unlock karein")
              : (name != null
                  ? "$name se baat karo, jab mann kare"
                  : "Jo mann mein hai, wahi karo — bina kisi rukawat ke"),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 18),
        if (_discountPercent > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent, width: 1.2),
            ),
            child: Text(
              "$_discountPercent% DISCOUNT",
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5),
            ),
          ),
        const SizedBox(height: 14),
        if (_plans.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_plans[_selectedPlanIndex]['originalPrice'] != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: Text(
                    "₹${_plans[_selectedPlanIndex]['originalPrice']}",
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 18,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white38),
                  ),
                ),
              Text(
                "₹${_plans[_selectedPlanIndex]['price']}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    height: 1.0),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(_durationLabel,
            style: TextStyle(
                color: Colors.pinkAccent.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _heroPhotoPlaceholder() {
    return Container(
      color: Colors.black26,
      child: const Icon(Icons.favorite_rounded, color: Colors.white54, size: 44),
    );
  }

  Widget _buildFeatureList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildFeatureRow(Icons.call_rounded, const Color(0xFF6A3EA1),
              "Voice Calls", "Jab bhi mann ho, seedhe baat karo"),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.favorite_rounded, Colors.pinkAccent,
              "Private Chats", "Jo maan mai hai, woh saare baat karo"),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.camera_alt_rounded, Colors.orangeAccent,
              "Exclusive Photos",
              "Sirf premium members ke liye special photos"),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
      IconData icon, Color color, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(width: 24),
                Expanded(
                  child: Text("100% Safe",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900)),
                ),
                Icon(Icons.volume_up_rounded, color: Colors.white24, size: 18),
              ],
            ),
            const SizedBox(height: 4),
            const Text("Tumhari privacy humesha safe hai",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),
            _buildSafetyRow(Icons.block_rounded, Colors.redAccent,
                "Screenshots blocked", "Poori app mein koi screenshot nahi le sakta"),
            const SizedBox(height: 16),
            _buildSafetyRow(Icons.delete_outline_rounded, Colors.orangeAccent,
                "Auto-delete chats",
                "Private mode se niklo toh sab messages apne aap delete"),
            const SizedBox(height: 16),
            _buildSafetyRow(Icons.lock_outline_rounded, Colors.tealAccent,
                "No data stored",
                "Na phone mein na server pe, kuch bhi save nahi hota"),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyRow(
      IconData icon, Color color, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTestimonialCard() {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: _testimonialController,
        itemCount: _testimonials.length,
        onPageChanged: (i) => setState(() => _testimonialPage = i),
        itemBuilder: (context, i) {
          final t = _testimonials[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.person, color: Colors.white38, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t['name']!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                            Text(t['place']!,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                      Row(
                        children: List.generate(
                            5,
                            (i) => const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Text(
                      t['quote']!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: Colors.pinkAccent, size: 14),
                      const SizedBox(width: 6),
                      Text("${t['likes']} found this helpful",
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_testimonials.length, (i) {
        final isActive = i == _testimonialPage;
        return GestureDetector(
          onTap: () => _testimonialController.animateToPage(i,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.pinkAccent
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildJoinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.4)),
        color: Colors.pinkAccent.withValues(alpha: 0.08),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_rounded, color: Colors.pinkAccent, size: 18),
          SizedBox(width: 8),
          Text("Join 50,000+ premium members",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: Colors.white38, width: 0.8))),
        padding: const EdgeInsets.only(bottom: 1),
        child: Text(text,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ),
    );
  }

  Widget _buildActualBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF1E1E1E), Color(0xFF1A080E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {
                  final selectedPlan = _plans[_selectedPlanIndex];
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PaymentScreen(
                                offerId: selectedPlan['id'],
                                offerName: selectedPlan['name'],
                                price: selectedPlan['price'],
                                duration: selectedPlan['duration'],
                                googlePlayId: selectedPlan['googlePlayId'],
                                googlePlaySubId:
                                    selectedPlan['googlePlaySubId'],
                                rzpPlanId: selectedPlan['rzpPlanId'],
                              )));
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: _isUpiEnabled
                          ? Image.asset('assets/gpay_logo.png',
                              height: 22,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.payment,
                                      color: Colors.black, size: 22))
                          : const Icon(Icons.shop_rounded,
                              color: Colors.blue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Pay via",
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Flexible(
                                  child: Text(
                                      _isUpiEnabled ? "GPay/UPI" : "Play Store",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis)),
                              const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white, size: 18),
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
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.pink))
                    : ElevatedButton(
                        onPressed: _claimOffer,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25)),
                            elevation: 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                                child: Text(
                                    _isUpiEnabled
                                        ? "Pay ₹${_plans.isNotEmpty ? _plans[_selectedPlanIndex]['price'] : widget.price}"
                                        : "Pay via Play Store",
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis)),
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
