import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'verification_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? currentUser;

  @override
  void initState() { super.initState(); _loadUserData(); }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_data');
    if (data != null) setState(() => currentUser = jsonDecode(data));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17), elevation: 0,
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsPage())), icon: const Icon(Icons.settings))],
      ),
      body: currentUser == null ? const Center(child: CircularProgressIndicator()) : Stack(children: [
        SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 40),
          Text(currentUser!['name'] ?? 'User', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
          if (currentUser!['isVerified'] == true) 
            const Padding(padding: EdgeInsets.only(top: 4), child: Row(children: [Icon(Icons.verified, color: Colors.blueAccent, size: 20), SizedBox(width: 8), Text('Verified Profile', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))])),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.location_on, color: Colors.orangeAccent, size: 20), const SizedBox(width: 8), Text((currentUser!['area'] != null && currentUser!['area'] != "Unknown" && currentUser!['area'] != "") ? "${currentUser!['area']}, ${currentUser!['city'] ?? ''}" : (currentUser!['city'] ?? 'Location'), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 18))]),
          const SizedBox(height: 40),
          _buildDetailRow(Icons.calendar_month, 'Age', currentUser!['age']?.toString() ?? '18'),
          _buildDetailRow(Icons.groups, 'Position', currentUser!['position'] ?? 'Any'),
          _buildDetailRow(Icons.home, 'Place to meet', currentUser!['havePlace'] ?? 'NO'),
          if (currentUser!['isVerified'] != true) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.verified, color: Colors.blueAccent), SizedBox(width: 10), Text('Get Verified', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]),
                const SizedBox(height: 8),
                const Text('Duniya ko batao ki aap real ho. Blue Tick paane ke liye ek selfie upload karein.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VerificationPage())), style: TextButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20)), child: const Text('Start Verification', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ]),
            ),
          ],
          const SizedBox(height: 150)
        ])),
        Positioned(bottom: 40, left: 24, right: 24, child: Container(height: 55, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)]), borderRadius: BorderRadius.circular(30)), child: Material(color: Colors.transparent, child: InkWell(onTap: () async { if (await Navigator.push(context, MaterialPageRoute(builder: (c) => const EditProfilePage())) == true) _loadUserData(); }, child: const Center(child: Text('Edit Details', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)))))))
      ]),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String val) => Padding(padding: const EdgeInsets.only(bottom: 25), child: Row(children: [Icon(icon, color: Colors.white54, size: 24), const SizedBox(width: 16), Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)), const Spacer(), Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]));
}
