import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'offer_trial_screen.dart';

class OfferScreen extends StatefulWidget {
  const OfferScreen({super.key});

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshConfig();
  }

  Future<void> _refreshConfig() async {
    setState(() => _isRefreshing = true);
    await AppConfigService().fetchReviewMode(forceRefresh: true);
    if (mounted) setState(() => _isRefreshing = false);
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      "SPECIAL OFFERS",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 14,
                      ),
                    ),
                    if (_isRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)),
                      ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Icon(Icons.auto_awesome, color: Colors.orangeAccent, size: 40),
              const SizedBox(height: 16),
              const Text(
                "Unlock Premium Access",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                child: Text(
                  "Choose a plan to unlock all features, images, and unlimited chat.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: offers.length,
                  itemBuilder: (context, index) {
                    final offer = offers[index];
                    return _buildOfferCard(context, offer, index);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  "Subscription will auto-renew. Cancel anytime in settings.",
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferCard(BuildContext context, dynamic offer, int index) {
    final bool isBestValue = index == 2;
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isBestValue ? Colors.orangeAccent : Colors.white10,
            width: isBestValue ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBestValue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "BEST VALUE",
                        style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900),
                      ),
                    ),
                  Text(
                    offer['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${offer['duration']} Days Access",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "₹${offer['price']}",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 24, fontWeight: FontWeight.w900),
                ),
                Text(
                  index == 0 ? "Per Day" : (index == 1 ? "Per Week" : "Per Month"),
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
