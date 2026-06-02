import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'cancel_membership_screen.dart';
import 'package:gogo/features/premium/screens/trial_onboarding_screen.dart';

class PremiumSettingsPage extends StatefulWidget {
  const PremiumSettingsPage({super.key});

  @override
  State<PremiumSettingsPage> createState() => _PremiumSettingsPageState();
}

class _PremiumSettingsPageState extends State<PremiumSettingsPage> {
  @override
  void initState() {
    super.initState();
    // Background sync to ensure data is latest, but don't block UI
    PremiumService().syncSubscription();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM, yyyy').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'trial_active': return 'Trial Active';
      case 'active': return 'Premium Active';
      case 'payment_failed': return 'Payment Failed';
      case 'cancelled': return 'Cancelled';
      case 'expired': return 'Expired';
      default: return 'Not Subscribed';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'trial_active': return Colors.greenAccent;
      case 'active': return Colors.orangeAccent;
      case 'payment_failed': return Colors.redAccent;
      case 'cancelled': return Colors.grey;
      case 'expired': return Colors.red;
      default: return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppConfigService().isStandardModeNotifier,
      builder: (context, isStandardMode, _) {
        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: UserRepository().userNotifier,
          builder: (context, userData, _) {
            if (userData == null) {
              return const Scaffold(
                backgroundColor: Color(0xFF0F0F0F),
                body: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
              );
            }

            if (isStandardMode) {
              return _buildReviewModeSettings();
            }

            final sub = userData['subscription'] ?? {};
            final isPremium = userData['isPremium'] ?? false;
            final status = sub['status'] ?? (isPremium ? 'active' : 'none');

            return Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              appBar: AppBar(
                backgroundColor: const Color(0xFF2A0D17),
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Subscription Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                          colors: [const Color(0xFF1E1E1E), const Color(0xFF2A0D17).withValues(alpha: 0.5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _getStatusColor(status).withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(Icons.workspace_premium, color: Colors.black, size: 28),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_getStatusText(status), 
                                    style: TextStyle(color: _getStatusColor(status), fontSize: 20, fontWeight: FontWeight.bold)),
                                  Text('Plan: ${userData['premiumPlan'] ?? 'N/A'}', 
                                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(color: Colors.white10),
                          ),
                          
                          _buildBillingRow('Subscription ID', sub['id'] ?? 'N/A'),
                          _buildBillingRow('Purchase Date', _formatDate(sub['startDate'])),
                          _buildBillingRow('Next Bill', _formatDate(sub['nextBillingDate'])),
                          _buildBillingRow('Total Amount Paid', '₹ ${sub['totalAmountPaid'] ?? 0}', isBold: true),
                          _buildBillingRow('Auto-Renew', (sub['autoRenew'] ?? true) ? 'Enabled' : 'Disabled'),
                          
                          if (sub['paymentMethod'] != null)
                            _buildBillingRow('Payment Method', sub['paymentMethod']),

                          const SizedBox(height: 10),

                          if (isPremium && sub['autoRenew'] == true && (status == 'active' || status == 'trial_active'))
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelMembershipPage()));
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('MANAGE AUTO-PAY', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          
                          if (status == 'cancelled' && isPremium)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TrialOnboardingScreen(forceShow: true)));
                                  },
                                  icon: const Icon(Icons.bolt, color: Colors.black),
                                  label: const Text("REACTIVATE MEMBERSHIP", style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Payment History Section
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text('Payment History', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
                    _buildPaymentHistory(userData),

                    const SizedBox(height: 30),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text('Frequently Asked Questions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
                    _buildFAQTile('How does the ₹1 trial work?', 'You are charged ₹1 immediately to verify your payment method. The full subscription starts automatically after 24 hours.'),
                    _buildFAQTile('Can I cancel anytime?', 'Yes, you can cancel your subscription from this page or directly from your UPI app (GPay/PhonePe).'),
                    _buildFAQTile('Refund policy?', 'The ₹1 verification charge is non-refundable. Monthly subscription charges are also non-refundable once processed.'),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBillingRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildPaymentHistory(Map<String, dynamic> userData) {
    final history = (userData['paymentHistory'] as List?)?.reversed.toList() ?? [];
    if (history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text('No transactions found.', style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length > 5 ? 5 : history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['status'] ?? 'Success', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(_formatDate(item['timestamp']), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              Text('₹ ${item['amount']}', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFAQTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        iconColor: Colors.orangeAccent,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(answer, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewModeSettings() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: const Text('Member Information', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user_rounded, color: Colors.blueAccent, size: 80),
            const SizedBox(height: 24),
            const Text(
              "Account Status: Active",
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "Your GoGo account is in good standing.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Enjoy full access to our community. If you have any questions, please contact our support team.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
