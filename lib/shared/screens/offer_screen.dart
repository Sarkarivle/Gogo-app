import 'package:flutter/material.dart';
import 'offer_trial_screen.dart';

class OfferScreen extends StatelessWidget {
  const OfferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This screen is now deprecated. It redirects immediately to OfferTrialScreen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pop(context); // Remove the OfferScreen from stack
        OfferTrialScreen.show(context);
      }
    });

    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      ),
    );
  }
}
