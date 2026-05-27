import 'package:flutter/material.dart';

class CommunityGuidelinesModal extends StatelessWidget {
  final VoidCallback onAccept;

  const CommunityGuidelinesModal({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.gavel_rounded, color: Colors.orangeAccent, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            "Community Guidelines",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            "Safe environment banaye rakhne ke liye kripya in niyam ka palan karein:",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "Niyam todne par aapka account hamesha ke liye BAN kar diya jayega.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onAccept();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              elevation: 0,
            ),
            child: const Text("I AGREE & START", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          const SafeArea(child: SizedBox(height: 10)),
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
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
