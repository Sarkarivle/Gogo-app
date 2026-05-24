import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/app_visibility_coordinator.dart';
import 'login_screen.dart';
import 'premium_settings_screen.dart';
import 'contact_us_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, String> policyUrls = {};

  @override
  void initState() {
    super.initState();
    _fetchPolicies();
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
          const SnackBar(content: Text('Link not available yet')),
        );
      }
      return;
    }

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch link')),
        );
      }
    }
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
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildPremiumCard(context),
            const SizedBox(height: 30),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  _buildSettingsTile(context, Icons.verified_user_outlined, 'KYC Verification'),
                  _buildSettingsTile(context, Icons.privacy_tip_outlined, 'Privacy Policy', 
                    onTap: () => _launchUrl('privacy_policy')),
                  _buildSettingsTile(context, Icons.description_outlined, 'Terms & Conditions',
                    onTap: () => _launchUrl('terms_conditions')),
                  _buildSettingsTile(context, Icons.receipt_long_outlined, 'Invoice'),
                  _buildSettingsTile(context, Icons.security_outlined, 'Safety & Child Protection',
                    onTap: () => _launchUrl('safety_protection')),
                  _buildSettingsTile(context, Icons.mail_outline_rounded, 'Contact Us',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ContactUsScreen()))),
                  _buildSettingsTile(context, Icons.info_outline_rounded, 'About Us',
                    onTap: () => _launchUrl('about_us')),
                  _buildSettingsTile(context, Icons.block_flipped, 'Blocked Users'),
                  _buildSettingsTile(context, Icons.no_accounts_outlined, 'Deactivate Account'),
                  _buildSettingsTile(context, Icons.visibility_off_outlined, 'Hide my app', 
                    onTap: () => AppVisibilityCoordinator().toggleHideMode(context)),
                  _buildSettingsTile(context, Icons.logout_rounded, 'Logout', isLast: true, color: Colors.redAccent, onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                    }
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('V 2.6.5', style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumCard(BuildContext context) {
    return Container(
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
      child: Column(children: [
        Row(children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle), 
            child: const Center(child: Text('P', style: TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.w900)))
          ),
          const SizedBox(width: 16),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Premium Membership', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('Unlocked all features', style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PremiumSettingsPage())),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          child: const Text('Premium Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, {bool isLast = false, Color? color, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: ListTile(
        leading: Icon(icon, color: color ?? Colors.orangeAccent, size: 22),
        title: Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3), size: 20),
        onTap: onTap ?? () {},
      ),
    );
  }
}
