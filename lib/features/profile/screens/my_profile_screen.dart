import 'package:flutter/material.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'package:gogo/features/verification/screens/verification_screen.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

import 'package:gogo/features/premium/providers/premium_service.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: UserRepository().userNotifier,
      builder: (context, currentUser, _) {
        if (currentUser == null) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator()));

        final String name = currentUser['name'] ?? 'User';
        final String statusLabel = PremiumService().accountStatusLabel;
        final bool isVerified = currentUser['isVerified'] == true;
        final bool isSubmitted = currentUser['verificationSubmitted'] == true;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1C1421), // Baingani Black
            elevation: 0,
            title: const Text('My Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            actions: [
              IconButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsPage())),
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
              )
            ],
          ),
          body: Stack(
            children: [
              // Background Glow
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orangeAccent.withValues(alpha: 0.05),
                  ),
                ),
              ),
              
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section - Focused on Name and Status
                    Row(
                      children: [
                        // Profile Icon Container
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 1.5),
                          ),
                          child: const CircleAvatar(
                            radius: 32,
                            backgroundColor: Color(0xFF222222),
                            child: Icon(Icons.person_rounded, color: Colors.white10, size: 40),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isVerified) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 22),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (statusLabel == "PREMIUM" || statusLabel == "GOLD (TRIAL)")
                                          ? Colors.orangeAccent.withValues(alpha: 0.1) 
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        color: (statusLabel == "PREMIUM" || statusLabel == "GOLD (TRIAL)") ? Colors.orangeAccent : Colors.white60,
                                        fontSize: 11, 
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.location_on_rounded, color: Colors.white24, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    (currentUser['city'] ?? 'Location not set'),
                                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Main Edit Button (Clear and Easy to see)
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EditProfilePage())),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text("Edit My Details", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF222222),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        elevation: 0,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    const Text("PROFILE INFO", style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 16),

                    // Info Section - Simplified List
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          _buildModernDetail(Icons.calendar_today_rounded, 'My Age', '${currentUser['age'] ?? 18} Years'),
                          _buildDivider(),
                          _buildModernDetail(Icons.person_outline_rounded, 'My Position', currentUser['position'] ?? 'Set now'),
                          _buildDivider(),
                          _buildModernDetail(Icons.home_outlined, 'Place to Meet', currentUser['havePlace'] ?? 'NO'),
                        ],
                      ),
                    ),

                    if (!isVerified) ...[
                      const SizedBox(height: 24),
                      // Verification Card (Clean and Simple)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1C2E),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_rounded, color: Colors.blueAccent, size: 30),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSubmitted ? 'Checking Selfie' : 'Get Verified',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    isSubmitted ? 'Admin is reviewing it' : 'Add a blue tick to profile',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (!isSubmitted)
                              ElevatedButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VerificationPage())),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernDetail(IconData icon, String label, String val) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white38, size: 20),
        ),
        const SizedBox(width: 16),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Divider(color: Colors.white.withValues(alpha: 0.03), height: 1),
  );
}
