import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gogo/features/profile/screens/profile_detail_screen.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/services/ad_service.dart';
import 'package:gogo/core/services/permission_manager.dart';
import 'package:gogo/features/call/providers/call_service.dart';
import 'package:gogo/features/call/screens/fake_call_screen.dart';
import 'package:gogo/features/premium/repositories/premium_repository.dart';
import 'package:gogo/features/premium/repositories/call_credits_repository.dart';
import 'package:gogo/shared/screens/buy_call_credits_screen.dart';

class ProfileCard extends StatelessWidget {
  final String distance;
  final String? fullDistance; // New: Raw distance without 20km privacy rule
  final String city;
  final String area;
  final String name;
  final String phone;
  final Color nameColor;
  final int age;
  final String position;
  final String havePlace;
  final int? likedBy;
  final bool isVerified;
  final bool isOnline;
  final bool hideFarDistance;
  final String? photoUrl;
  final String? tagline;
  final bool isCreator;

  const ProfileCard({
    super.key,
    required this.distance,
    this.fullDistance,
    required this.city,
    required this.area,
    required this.name,
    required this.phone,
    required this.nameColor,
    required this.age,
    required this.position,
    required this.havePlace,
    this.likedBy,
    this.isVerified = false,
    this.isOnline = false,
    this.hideFarDistance = false,
    this.photoUrl,
    this.tagline,
    this.isCreator = false,
  });

  Future<void> _handleCallTap(BuildContext context) async {
    // Creator profiles have no real device on the other end — route through
    // the call-credits system and a simulated call instead of real WebRTC signaling.
    if (isCreator) {
      final allowed = await CallCreditsRepository().checkAndConsumeCredit(phone);
      if (!context.mounted) return;
      if (!allowed) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCallCreditsScreen()));
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FakeCallScreen(name: name, photoUrl: photoUrl)),
      );
      return;
    }

    if (!PremiumRepository().checkAccessAndShowOffer(context, feature: 'call', isStrict: true)) {
      return;
    }

    final hasPermission = await PermissionManager().checkAndRequestCallPermissions(context, isVideo: true);
    if (hasPermission) {
      CallService().startCall(phone, name, isVideo: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Show  ad before navigating to profile details
        AdService().showInterstitialAd(onAdClosed: () {
          ProfileDetailPage.navigate(
            context,
            name: name,
            phone: phone,
            distance: (fullDistance != null && fullDistance!.isNotEmpty) ? fullDistance! : distance,
            city: city,
            area: area,
            age: age,
            position: position,
            havePlace: havePlace,
            isVerified: isVerified,
            isOnline: isOnline,
            photoUrl: photoUrl,
          );
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background photo (cached — avoids re-downloading the same photo repeatedly)
            if (photoUrl != null && photoUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: ApiService.getSecureUrl(photoUrl),
                fit: BoxFit.cover,
                memCacheWidth: 480,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) => _placeholder(),
                errorWidget: (context, url, error) => _placeholder(),
              )
            else
              _placeholder(),

            // Bottom dark gradient overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),

            // Top-left: Online status pill
            if (isOnline)
              Positioned(
                top: 10,
                left: 10,
                child: _onlineBadge(),
              ),

            // Top-right: Verified badge
            if (isVerified)
              Positioned(
                top: 10,
                right: 10,
                child: _verifiedBadge(),
              ),

            // Text content
            Positioned(
              left: 12,
              right: 60,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _ageTag(),
                  if (tagline != null && tagline!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      tagline!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Bottom-right corner: Call button
            Positioned(
              right: 10,
              bottom: 12,
              child: GestureDetector(
                onTap: () => _handleCallTap(context),
                child: _callButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _onlineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1FB855),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 7),
          SizedBox(width: 4),
          Text(
            'Online',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _verifiedBadge() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
      ),
      child: const Icon(Icons.verified, color: Colors.blueAccent, size: 20),
    );
  }

  Widget _ageTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🇮🇳', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$age',
            style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _callButton() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF5C93), Color(0xFFEC297B)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A2E83), Color(0xFF2D1B4E)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, color: Colors.white38, size: 56),
      ),
    );
  }
}
