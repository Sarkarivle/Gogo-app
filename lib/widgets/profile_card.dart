import 'package:flutter/material.dart';
import '../screens/profile_detail_screen.dart';
import 'blinking_dot.dart';

class ProfileCard extends StatelessWidget {
  final String distance;
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

  const ProfileCard({
    super.key,
    required this.distance,
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
  });

  @override
  Widget build(BuildContext context) {
    // Determine the best location name to show before distance
    String locName = "";
    final String safeArea = area.toString();
    final String safeCity = city.toString();

    if (safeArea.isNotEmpty && safeArea.toLowerCase() != "unknown" && safeArea.toLowerCase() != "null") {
      locName = safeArea;
    } else if (safeCity.isNotEmpty && safeCity.toLowerCase() != "unknown" && safeCity.toLowerCase() != "null") {
      locName = safeCity;
    }

    String cleanDistance = distance.replaceAll(' away', '');
    String locationDisplay = cleanDistance;
    if (locName.isNotEmpty) {
      if (cleanDistance.isNotEmpty) {
        locationDisplay = "$locName, $cleanDistance";
      } else {
        locationDisplay = locName;
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileDetailPage(
              name: name,
              phone: phone,
              distance: distance,
              city: city,
              area: area,
              age: age,
              position: position,
              havePlace: havePlace,
              isVerified: isVerified,
              isOnline: isOnline,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOnline) ...[
              const Row(
                children: [
                  BlinkingDot(),
                  SizedBox(width: 6),
                  Text(
                    'Online Now',
                    style: TextStyle(
                      color: Color(0xFF00C853),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(children: [
              const Icon(Icons.near_me_rounded, size: 14, color: Colors.orangeAccent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  locationDisplay,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(color: nameColor, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blueAccent, size: 16),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow('Age', age.toString()),
            _buildInfoRow('Position', position),
            _buildInfoRow('Have Place', havePlace),
            const Spacer(),
            if (likedBy != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.amber.shade400, Colors.orange.shade400]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Liked by $likedBy',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(children: [
        Text('$label ', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value, 
            style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
