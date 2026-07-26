import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/providers/payment_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

/// Purchase screen for call credits — a separate currency from Premium,
/// spent one at a time on fake-call attempts to a creator (see
/// CallCreditsRepository / ChatController.checkCallCredit). Deliberately a
/// simpler screen than OfferTrialScreen (no confetti/video/exit-offer
/// flourishes) since this is a lower-stakes, high-frequency purchase, not the
/// primary subscription upsell.
///
/// Packs are read from the same '/api/payment/special-offers' Config the
/// premium plans come from — any offer entry tagged `type: 'credits'` shows
/// up here. If none are configured yet, a sensible fallback list is used so
/// the feature works before an admin adds real packs.
class BuyCallCreditsScreen extends StatefulWidget {
  const BuyCallCreditsScreen({super.key});

  @override
  State<BuyCallCreditsScreen> createState() => _BuyCallCreditsScreenState();
}

class _BuyCallCreditsScreenState extends State<BuyCallCreditsScreen> {
  static const List<Map<String, dynamic>> _fallbackPacks = [
    {'id': 'call_credits_5', 'name': '5 Call Credits', 'price': 49, 'credits': 5},
    {'id': 'call_credits_20', 'name': '20 Call Credits', 'price': 149, 'credits': 20},
    {'id': 'call_credits_50', 'name': '50 Call Credits', 'price': 299, 'credits': 50},
  ];

  late List<Map<String, dynamic>> _packs;
  int _selectedIndex = 1;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _packs = _loadPacks();
  }

  List<Map<String, dynamic>> _loadPacks() {
    final offersConfig = AppConfigService().offersConfig;
    final List<dynamic> allOffers = offersConfig?['offers'] ?? [];
    final creditOffers = allOffers
        .where((o) => o is Map && o['type'] == 'credits')
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    return creditOffers.isNotEmpty ? creditOffers : _fallbackPacks;
  }

  Future<void> _buyPack() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";
      final phone = userData['phone']?.toString();
      if (phone == null) throw "Phone not found";

      final pack = _packs[_selectedIndex];

      final orderData = await PaymentService.createOrder(
        phone,
        gateway: 'razorpay',
        amount: (pack['price'] as num).toInt(),
        offerId: pack['id']?.toString(),
        googlePlayId: pack['googlePlayId']?.toString(),
        duration: 0,
        isSubscription: false,
      );

      if (orderData['success'] != true) {
        throw orderData['message']?.toString() ?? "Order creation failed";
      }

      final gateway = orderData['gateway']?.toString().toLowerCase() ?? 'razorpay';
      final handler = PaymentService.getHandler(gateway);
      final orderId = orderData['orderId'];

      await handler.initiatePayment(
        {...orderData, 'phone': phone},
        (successData) => _verifyAndCredit(successData, orderId, pack),
        (err) => _showError(err.toString()),
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndCredit(Map<String, dynamic> successData, String? orderId, Map<String, dynamic> pack) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userData = UserRepository().currentUser;
      if (userData == null) throw "Session lost";

      final verifyRes = await PaymentService.verifyPayment(userData['phone'], {
        ...successData,
        'gateway': successData['gateway'] ?? 'razorpay',
        'orderId': orderId,
        'merchantTransactionId': orderId,
      });

      if (verifyRes['success'] == true) {
        // Refresh local user so the new callCredits balance is reflected
        // everywhere immediately — note: no PremiumService call here, this
        // purchase never touches premium/subscription state.
        if (verifyRes['user'] != null) {
          await UserRepository().updateLocalUser(verifyRes['user']);
        }
        if (mounted) {
          final newBalance = verifyRes['user']?['callCredits'];
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(newBalance != null ? "$newBalance call credits added! 🎉" : "Call credits added! 🎉")),
          );
        }
      } else {
        throw verifyRes['message']?.toString() ?? "Verification failed";
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _error = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Buy Call Credits', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.call_rounded, color: Colors.orangeAccent, size: 56),
              const SizedBox(height: 12),
              const Text(
                "Out of call credits",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                "Buy more credits to keep calling",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.separated(
                  itemCount: _packs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final pack = _packs[index];
                    final isSelected = _selectedIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIndex = index),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white12, width: isSelected ? 2 : 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                              color: isSelected ? Colors.orangeAccent : Colors.white38,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                pack['name']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '₹${pack['price']}',
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                ),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _buyPack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : const Text('Buy Credits', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
