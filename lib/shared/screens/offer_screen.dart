import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'offer_trial_screen.dart';

class OfferScreen extends StatefulWidget {
  const OfferScreen({super.key});

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  bool _isRefreshing = false;
  Timer? _timer;
  final ValueNotifier<int> _secondsRemaining = ValueNotifier<int>(900); // 15 minutes
  Map<String, String> policyUrls = {
    'terms_conditions': 'https://gogoapp.in/terms',
    'privacy_policy': 'https://gogoapp.in/privacy',
    'refund_policy': 'https://gogoapp.in/refund',
  };

  @override
  void initState() {
    super.initState();
    _refreshConfig();
    _fetchPolicies();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining.value > 0) {
        _secondsRemaining.value--;
      } else {
        _timer?.cancel();
      }
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
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

  Future<void> _refreshConfig() async {
    setState(() => _isRefreshing = true);
    await AppConfigService().fetchReviewMode(forceRefresh: true);
    if (mounted) setState(() => _isRefreshing = false);
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

  @override
  Widget build(BuildContext context) {
    final offersConfig = AppConfigService().offersConfig;
    final List<dynamic> offers = offersConfig?['offers'] ?? [
      { 'id': 'daily', 'name': '1 Day Free', 'price': 19, 'duration': 1, 'googlePlayId': '', 'googlePlaySubId': '', 'rzpPlanId': '' },
      { 'id': 'weekly', 'name': '7 Days Access', 'price': 100, 'duration': 7, 'googlePlayId': '', 'googlePlaySubId': '', 'rzpPlanId': '' },
      { 'id': 'monthly', 'name': '1 Month Premium', 'price': 199, 'duration': 30, 'googlePlayId': '', 'googlePlaySubId': '', 'rzpPlanId': '' }
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8.0, 4.0, 16.0, 0.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (_isRefreshing)
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    "LIMITED TIME OFFER: 50% OFF",
                    style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 10),
                const Icon(Icons.auto_awesome, color: Colors.orangeAccent, size: 40),
                const SizedBox(height: 10),
                const Text(
                  "Premium Member Bano!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                  child: Text(
                    "Sari rukawate khatam karo! Unlimited chat, photos aur videos call ka access pao.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                _buildBenefitsRow(),
                const SizedBox(height: 25),
                // Timer Widget
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, color: Colors.orangeAccent.withValues(alpha: 0.8), size: 16),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: _secondsRemaining,
                        builder: (context, seconds, child) {
                          return Text(
                            "Dhamaka Offer ${_formatTime(seconds)} me khatam hoga",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: offers.length,
                  itemBuilder: (context, index) {
                    final offer = offers[index];
                    // Custom Hinglish names for plans
                    String displayTitle = offer['name'];
                    if (offer['id'] == 'daily') displayTitle = "Aaj ka Mazaa";
                    if (offer['id'] == 'weekly') displayTitle = "Weekly Dhamaka";
                    if (offer['id'] == 'monthly') displayTitle = "Super Saver Pack";

                    return _buildOfferCard(context, { ...offer, 'name': displayTitle }, index);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  "1.2 Lakh+ users ne GoGo Premium try kiya hai!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.bold),
                ),
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
                        _buildSubscriptionBullet("Sabhi plans trial period ke baad standard ₹199/month par auto-renew honge."),
                        _buildSubscriptionBullet("Aap kisi bhi waqt Play Store settings se subscription cancel kar sakte hain."),
                        _buildSubscriptionBullet("Payment successful hone par premium features ka instant access mil jayega."),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 24),
                  child: Column(
                    children: [
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
                      const SizedBox(height: 16),
                      const Text(
                        "By continuing, you agree to our Terms & Privacy Policy.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
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

  Widget _buildSubscriptionBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Colors.orangeAccent, fontSize: 14)),
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

  Widget _buildBenefitsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          _benefitChip(Icons.chat_bubble, "Unlimited Chat"),
          _benefitChip(Icons.photo_library, "Photos"),
          _benefitChip(Icons.videocam, "Unlimited Video Call"),
          _benefitChip(Icons.verified, "Real Profiles"),
        ],
      ),
    );
  }

  Widget _benefitChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildOfferCard(BuildContext context, dynamic offer, int index) {
    final bool isSuperSaver = index == 2;
    final bool isMostPopular = index == 1;

    // Marketing Logic: Original prices to show massive discount
    int originalPrice = (offer['price'] as int) * 3;
    if (index == 2) originalPrice = 999; // Anchor for the 199 plan
    if (index == 1) originalPrice = 499; // Anchor for the 100 plan
    if (index == 0) originalPrice = 99;  // Anchor for the 19 plan

    String subtitle = "${offer['duration']} Days Access";
    if (index == 0) subtitle = "1 Day Access • Trial lekar dekho!";
    if (index == 1) subtitle = "7 Days Access • Best for starters";
    if (index == 2) subtitle = "30 Days Access • Unlimited Masti!";

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfferTrialScreen(
            offerId: offer['id'],
            name: offer['name'],
            price: (offer['price'] as num).toInt(),
            duration: (offer['duration'] as num).toInt(),
            googlePlayId: offer['googlePlayId'],
            googlePlaySubId: offer['googlePlaySubId'],
            rzpPlanId: offer['rzpPlanId'],
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: EdgeInsets.all(isSuperSaver ? 24 : 20), // Removed const as it's dynamic
        decoration: BoxDecoration(
          color: isSuperSaver ? Colors.pinkAccent.withValues(alpha: 0.15) : (isMostPopular ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSuperSaver ? Colors.pinkAccent : (isMostPopular ? Colors.orangeAccent : Colors.white10),
            width: isSuperSaver ? 2.5 : (isMostPopular ? 1.5 : 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSuperSaver)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.pinkAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "MOST VALUE - 80% OFF",
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                      ),
                    )
                  else if (isMostPopular)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "MOST POPULAR",
                        style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900),
                      ),
                    ),
                  Text(
                    offer['name'],
                    style: TextStyle(
                      color: Colors.white, 
                      fontSize: isSuperSaver ? 20 : 18, 
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: isSuperSaver ? Colors.pinkAccent : (isMostPopular ? Colors.orangeAccent : Colors.white54), fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: "₹",
                            style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.w300, decoration: TextDecoration.lineThrough),
                          ),
                          TextSpan(
                            text: "$originalPrice",
                            style: const TextStyle(color: Colors.white24, fontSize: 14, decoration: TextDecoration.lineThrough),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "₹",
                            style: TextStyle(
                              color: isSuperSaver ? Colors.pinkAccent : Colors.orangeAccent, 
                              fontSize: isSuperSaver ? 20 : 18, 
                              fontWeight: FontWeight.w300
                            ),
                          ),
                          TextSpan(
                            text: "${offer['price']}",
                            style: TextStyle(
                              color: isSuperSaver ? Colors.pinkAccent : Colors.orangeAccent, 
                              fontSize: isSuperSaver ? 30 : 24, 
                              fontWeight: FontWeight.w900
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
