import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/user_repository.dart';
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
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _fetchPolicies();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final data = await UserRepository().getCurrentUser();
    if (mounted) {
      setState(() {
        userData = data;
      });
    }
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            SettingsHeaderCard(userData: userData),
            const SizedBox(height: 24),
            PremiumMembershipCard(userData: userData),
            const SizedBox(height: 24),
            _buildAccountSection(),
            const SizedBox(height: 24),
            _buildPrivacySection(),
            const SizedBox(height: 24),
            _buildAppControlSection(),
            const SizedBox(height: 30),
            _buildFooter(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return SettingsSectionCard(
      title: "ACCOUNT",
      children: [
        SettingsRowItem(
          icon: Icons.verified_user_outlined,
          title: 'KYC Verification',
          subtitle: 'Verify your identity',
          onTap: () {},
        ),
        SettingsRowItem(
          icon: Icons.receipt_long_outlined,
          title: 'Invoice',
          subtitle: 'Billing & payment history',
          onTap: () {},
        ),
        SettingsRowItem(
          icon: Icons.block_flipped,
          title: 'Blocked Users',
          subtitle: 'Manage restricted contacts',
          onTap: () {},
        ),
        SettingsRowItem(
          icon: Icons.star_outline_rounded,
          title: 'Premium Settings',
          subtitle: 'Manage your subscription',
          isLast: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PremiumSettingsPage())),
        ),
      ],
    );
  }

  Widget _buildPrivacySection() {
    return SettingsSectionCard(
      title: "PRIVACY & SAFETY",
      children: [
        SettingsRowItem(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          subtitle: 'Read our data usage policy',
          onTap: () => _launchUrl('privacy_policy'),
        ),
        SettingsRowItem(
          icon: Icons.description_outlined,
          title: 'Terms & Conditions',
          subtitle: 'App usage rules & guidelines',
          onTap: () => _launchUrl('terms_conditions'),
        ),
        SettingsRowItem(
          icon: Icons.security_outlined,
          title: 'Safety & Child Protection',
          subtitle: 'Community safety guidelines',
          onTap: () => _launchUrl('safety_protection'),
        ),
        SettingsRowItem(
          icon: Icons.mail_outline_rounded,
          title: 'Contact Us',
          subtitle: 'Get help or report issues',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ContactUsScreen())),
        ),
        SettingsRowItem(
          icon: Icons.info_outline_rounded,
          title: 'About Us',
          subtitle: 'Know more about our mission',
          isLast: true,
          onTap: () => _launchUrl('about_us'),
        ),
      ],
    );
  }

  Widget _buildAppControlSection() {
    return SettingsSectionCard(
      title: "APP CONTROL",
      children: [
        SettingsRowItem(
          icon: Icons.visibility_off_outlined,
          title: 'Hide My App',
          subtitle: 'Stealth mode settings',
          iconColor: Colors.blueAccent,
          onTap: () => AppVisibilityCoordinator().toggleHideMode(context),
        ),
        SettingsDangerRow(
          icon: Icons.no_accounts_outlined,
          title: 'Deactivate Account',
          subtitle: 'Temporary account freeze',
          color: Colors.orangeAccent,
          onTap: () => _showDeactivateModal(context),
        ),
        SettingsDangerRow(
          icon: Icons.logout_rounded,
          title: 'Logout',
          subtitle: 'Sign out from your account',
          color: Colors.redAccent,
          isLast: true,
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            if (mounted) {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
            }
          },
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'V 2.6.5',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Text(
          'Crafted with ❤️ for our community',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.1), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _showDeactivateModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'Deactivate Account?',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              'This will temporarily hide your profile.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 32),
            _buildWarningItem('Your profile will disappear from discovery'),
            _buildWarningItem('Nobody will see your profile in feed'),
            _buildWarningItem('Existing chats will remain intact'),
            _buildWarningItem('Your premium membership will stay safe'),
            _buildWarningItem('Reactivate anytime by logging back in'),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _handleDeactivation(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: const Text('Confirm Deactivation', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: Text('Maybe later', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: Colors.orangeAccent.withValues(alpha: 0.5), size: 16),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> _handleDeactivation(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    );

    try {
      final user = await UserRepository().getCurrentUser();
      if (user != null) {
        final success = await UserRepository().deactivateAccount(user['phone'], 'User requested from settings');
        if (!context.mounted) return;

        if (success) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          if (context.mounted) {
            Navigator.of(context).pop(); // Close loading
            Navigator.pushAndRemoveUntil(
              context, 
              MaterialPageRoute(builder: (context) => const LoginScreen()), 
              (route) => false
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error deactivating: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to deactivate. Please try again.')),
      );
    }
  }
}

class SettingsHeaderCard extends StatelessWidget {
  final Map<String, dynamic>? userData;
  const SettingsHeaderCard({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final name = userData?['name'] ?? 'Incognito';
    final isPremium = userData?['isPremium'] ?? false;
    final imageUrl = (userData?['profileImages'] as List?)?.isNotEmpty == true ? userData!['profileImages'][0] : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: imageUrl != null 
                ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.orangeAccent, fontSize: 24, fontWeight: FontWeight.w900))))
                : Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.orangeAccent, fontSize: 24, fontWeight: FontWeight.w900))),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Colors.orangeAccent, Colors.deepOrange]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('PRO', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text("Manage your account & privacy", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumMembershipCard extends StatelessWidget {
  final Map<String, dynamic>? userData;
  const PremiumMembershipCard({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final isPremium = userData?['isPremium'] ?? false;
    final expiryDate = userData?['premiumExpiry'] ?? 'Never';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 1.5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A1A0A),
            Color(0xFF1A1A1A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isPremium ? '👑 PREMIUM MEMBER' : '✨ UPGRADE TO PREMIUM',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              if (isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isPremium ? (userData?['premiumPlanName'] ?? "आपका प्रीमियम प्लान सक्रिय है") : "प्रीमियम में अपग्रेड करें",
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            isPremium ? "वैधता: $expiryDate" : "अनलिमिटेड फीचर्स का आनंद लें",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildBenefitItem('Unlimited Interaction & Chat'),
          _buildBenefitItem('Instant Video Call Access'),
          _buildBenefitItem('Priority Profile Visibility'),
          const SizedBox(height: 24),
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PremiumSettingsPage())),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orangeAccent, Color(0xFFFF9000)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orangeAccent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Colors.black, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Premium Settings',
                    style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              "प्लान, बिलिंग और सदस्यता मैनेज करें",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.orangeAccent, size: 14),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class SettingsSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSectionCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class SettingsRowItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;
  final Color? iconColor;

  const SettingsRowItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (iconColor ?? Colors.orangeAccent).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor ?? Colors.orangeAccent, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.2), size: 14),
          ],
        ),
      ),
    );
  }
}

class SettingsDangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final bool isLast;

  const SettingsDangerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.2), size: 14),
          ],
        ),
      ),
    );
  }
}
