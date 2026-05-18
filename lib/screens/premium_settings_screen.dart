import 'package:flutter/material.dart';
import 'cancel_membership_screen.dart';

class PremiumSettingsPage extends StatelessWidget {
  const PremiumSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Premium Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Premium Status Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1E1E1E), const Color(0xFF2A0D17).withOpacity(0.5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.orangeAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('P', style: TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Premium Member', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          Text('Activated since: 15 May, 2026', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: Colors.white10),
                  ),
                  _buildBillingRow('Purchase date', '15 May, 2026'),
                  _buildBillingRow('Next Bill', '16 May, 2026'),
                  _buildBillingRow('Amount Paid', '₹ 1', isBold: true),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auto renews every month', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      TextButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelMembershipPage()));
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('CANCEL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Frequently asked questions', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            _buildFAQTile('What are the benefits of buying Premium?', 'Allows you to talk to other users and unlocks exclusive matching features.'),
            _buildFAQTile('How can I get it at cheap prices?', 'We already offer subscriptions at discounted rates.'),
            _buildFAQTile('Refund policy?', 'There is currently no refund policy. You can cancel autopay anytime.'),
            _buildFAQTile('Can I gift my membership?', 'Membership is mapped to a specific profile and is not transferable.'),
            _buildFAQTile('How can I cancel in the future?', 'You can cancel autopay from your payment app or contact support.'),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildFAQTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(question, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          iconColor: Colors.orangeAccent,
          collapsedIconColor: Colors.white38,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(answer, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
