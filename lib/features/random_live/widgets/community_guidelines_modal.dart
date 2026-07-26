import 'package:flutter/material.dart';

class CommunityGuidelinesModal extends StatelessWidget {
  final VoidCallback onAccept;

  const CommunityGuidelinesModal({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Colors.orangeAccent, size: 36),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Community Guidelines",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Safe environment banaye rakhne ke liye kripya in niyam ka palan karein:",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  _buildGuideline(Icons.no_adult_content_rounded, "No Nudity or Sexual Content", "Kissi bhi tarah ki ashlilata sakht mana hai. Pakde jane par turant ban."),
                  const SizedBox(height: 16),
                  _buildGuideline(Icons.sentiment_very_dissatisfied_rounded, "No Harassment", "Dusre users ke saath badtameezi ya bullying na karein."),
                  const SizedBox(height: 16),
                  _buildGuideline(Icons.paid_rounded, "No Scams or Asking Money", "Kisi bhi user se paise mangna ya fraud karna sakht mana hai."),
                  const SizedBox(height: 16),
                  _buildGuideline(Icons.report_gmailerrorred_rounded, "Report Misbehavior", "Agar koi niyam todta hai, toh use turant Report karein."),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "Niyam todne par aapka account hamesha ke liye BAN kar diya jayega.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Text("Cancel", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onAccept();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("I Agree", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SafeArea(child: SizedBox(height: 0)),
        ],
      ),
    );
  }

  Widget _buildGuideline(IconData icon, String title, String desc) {
    return Row(
      children: [
        Icon(icon, color: Colors.orangeAccent, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(desc, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
