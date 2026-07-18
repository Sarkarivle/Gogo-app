import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';

class CancelMembershipPage extends StatefulWidget {
  const CancelMembershipPage({super.key});

  @override
  State<CancelMembershipPage> createState() => _CancelMembershipPageState();
}

class _CancelMembershipPageState extends State<CancelMembershipPage> {
  int? _selectedReasonIndex;
  final TextEditingController _otherReasonController = TextEditingController();
  bool _isProcessing = false;

  final List<String> _reasons = [
    "Don't use it that much.",
    "Don't want to pay current amount.",
    "Other reasons"
  ];

  Future<void> _confirmCancellation() async {
    if (_selectedReasonIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a reason first")),
      );
      return;
    }

    // Show Premium Confirmation Popup (Big App Style)
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A0D17), Color(0xFF1A1A1A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 30),
              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 60),
              const SizedBox(height: 20),
              const Text("ARE YOU SURE?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
              const SizedBox(height: 15),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "You will lose access to unlimited matches and premium features once your current period ends.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: 30),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _processCancel();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("YES, CANCEL AUTO-PAY", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("KEEP PREMIUM", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processCancel() async {
    setState(() => _isProcessing = true);
    try {
      final response = await ApiService.post('/api/payment/cancel', {
        'reason': _reasons[_selectedReasonIndex!],
        'details': _otherReasonController.text,
      });
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        // Sync local status immediately
        await PremiumService().syncSubscription();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Subscription Cancelled! Access remains until expiry."), backgroundColor: Colors.orange),
          );
          Navigator.pop(context); // Go back to settings
        }
      } else {
        throw data['message'] ?? "Cancellation failed";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

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
        title: const Text('Cancel Membership', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text('😢', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 20),
            const Text(
              "We are sorry to see you go. What's the main reason for cancelling?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ...List.generate(_reasons.length, (index) {
              bool isSelected = _selectedReasonIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedReasonIndex = index),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _reasons[index],
                          style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 16),
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white30, width: 2),
                          color: isSelected ? Colors.orangeAccent : Colors.transparent,
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (_selectedReasonIndex == 2) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _otherReasonController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Please specify your reason in brief...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 60),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isProcessing ? null : _confirmCancellation,
                        borderRadius: BorderRadius.circular(30),
                        child: Center(
                          child: _isProcessing 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('CANCEL MEMBERSHIP', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E), 
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(30),
                        child: const Center(
                          child: Text("KEEP PREMIUM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
