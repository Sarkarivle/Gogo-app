import 'package:flutter/material.dart';
import 'package:gogo/core/services/presence_manager.dart';
import 'package:gogo/core/services/ad_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/profile/repositories/moderation_repository.dart';
import 'package:gogo/features/chat/screens/chat_screen.dart';
import 'package:gogo/features/reviews/models/user_review.dart';
import 'package:gogo/features/reviews/repositories/review_repository.dart';

class ProfileDetailPage extends StatefulWidget {
  final String name;
  final String phone;
  final String distance;
  final String city;
  final String area;
  final int age;
  final String position;
  final String havePlace;
  final bool showMessageButton;
  final bool isVerified;
  final bool isOnline;

  const ProfileDetailPage({
    super.key,
    required this.name,
    required this.phone,
    required this.distance,
    required this.city,
    required this.area,
    required this.age,
    required this.position,
    required this.havePlace,
    this.showMessageButton = true,
    this.isVerified = false,
    this.isOnline = false,
  });

  static void navigate(BuildContext context, {
    required String name,
    required String phone,
    String distance = "Unknown",
    String city = "Unknown",
    String area = "Unknown",
    int age = 0,
    String position = "Unknown",
    String havePlace = "Unknown",
    bool showMessageButton = true,
    bool isVerified = false,
    bool isOnline = false,
  }) {
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
          showMessageButton: showMessageButton,
          isVerified: isVerified,
          isOnline: isOnline,
        ),
      ),
    );
  }

  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  bool _isLoading = false;
  late String _name;
  late String _distance;
  late String _city;
  late String _area;
  late int _age;
  late String _position;
  late String _havePlace;
  late bool _isVerified;
  List<UserReview> _reviews = [];

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _distance = widget.distance;
    _city = widget.city;
    _area = widget.area;
    _age = widget.age;
    _position = widget.position;
    _havePlace = widget.havePlace;
    _isVerified = widget.isVerified;

    _fetchReviews();

    // If age is 0 or city is Unknown, we probably need more data
    if (_age == 0 || _city == "Unknown") {
      _fetchFullProfile();
    }
  }

  Future<void> _fetchReviews() async {
    final reviews = await ReviewRepository().getReviews(widget.phone);
    if (mounted) {
      setState(() {
        _reviews = reviews;
      });
    }
  }

  Future<void> _fetchFullProfile() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      final userData = await UserRepository().fetchProfile(widget.phone);
      if (userData != null && mounted) {
        setState(() {
          _name = userData['name'] ?? _name;
          _city = userData['city'] ?? _city;
          _area = userData['area'] ?? _area;
          
          // Better Age Handling
          if (userData['age'] != null) {
            _age = userData['age'] is int ? userData['age'] : int.tryParse(userData['age'].toString()) ?? _age;
          } else if (userData['dobYear'] != null) {
            final year = int.tryParse(userData['dobYear'].toString());
            if (year != null && year > 1900) {
              _age = DateTime.now().year - year;
            }
          }

          _position = userData['position'] ?? _position;
          _havePlace = userData['havePlace'] ?? _havePlace;
          _isVerified = userData['isVerified'] ?? _isVerified;
          
          // Update distance if provided by the profile API
          final remoteDistance = userData['distance'] ?? userData['distanceStr'];
          if (remoteDistance != null && remoteDistance.toString().isNotEmpty) {
            _distance = remoteDistance.toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.white70),
                title: const Text('Report Profile', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                title: const Text('Block User', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _showBlockConfirmDialog();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Block User?', style: TextStyle(color: Colors.white)),
        content: const Text('Is user ko block karne ke baad aap ek dusre ko message nahi kar payenge.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () {
              final user = UserRepository().currentUser;
              if (user != null) {
                ModerationRepository().blockUser(blockerPhone: user['phone'], blockedPhone: widget.phone);
                Navigator.pop(context);
                Navigator.pop(context); // Go back from profile
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User blocked successfully')));
              }
            }, 
            child: const Text('BLOCK', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    String? selectedCategory;
    final otherReasonController = TextEditingController();
    bool isOtherSelected = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: StatefulBuilder(
                      builder: (context, setModalState) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.red, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Text('Report Profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Kyun report kar rahe hain?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('Aapki report private rakhi jayegi.', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                          const SizedBox(height: 20),
                          
                          _buildReportOption('Misbehavior / Bad Language', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildReportOption('Asking for Money / Scams', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildReportOption('Fake Photos / Profile', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildReportOption('Other Reason', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = true; });
                          }),

                          if (isOtherSelected) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: otherReasonController,
                              maxLines: 2,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Detail mein batayein...',
                                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: selectedCategory == null ? null : () => _submitReport(selectedCategory!, otherReasonController.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportOption(String title, String? selected, Function(String) onTap) {
    bool isSelected = selected == title;
    return InkWell(
      onTap: () => onTap(title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.2) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? Colors.orangeAccent : Colors.white24),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(String category, String detail) async {
    try {
      final user = UserRepository().currentUser;
      final myPhone = user?['phone'];
      if (myPhone == null) return;

      final success = await ModerationRepository().reportUser(
        reporterPhone: myPhone, 
        reportedPhone: widget.phone, 
        category: category,
        description: detail
      );

      if (mounted && success) {
        Navigator.pop(context); // Close sheet
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted successfully')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit report')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit report')));
    }
  }

  @override
  Widget build(BuildContext context) {
    String locName = "";
    if (_area.isNotEmpty && _area != "Unknown") {
      locName = _area;
    } else if (_city.isNotEmpty && _city != "Unknown") {
      locName = _city;
    }

    String cleanDistance = _distance
        .replaceAll(' away', '')
        .replaceAll('Within ', '')
        .replaceAll('Under ', '');
    String locationDisplay = "";
    
    if (cleanDistance.isNotEmpty && cleanDistance.toLowerCase() != "unknown") {
      locationDisplay = locName.isNotEmpty ? "$cleanDistance • $locName" : cleanDistance;
    } else {
      locationDisplay = locName;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: AdService().shouldShowAds ? 120 : 280,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF1C1421), // Baingani Black
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: _showMoreOptions,
                  )
                ],
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                  child: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF1C1421), Color(0xFF121212)],
                          ),
                        ),
                      ),
                      // Background pattern/icon area (Only show if NO ads are being displayed)
                      if (!AdService().shouldShowAds)
                        Center(
                          child: Icon(Icons.person_rounded, size: 120, color: Colors.white.withValues(alpha: 0.03)),
                        ),
                      // Top Overlay for better visibility of back button
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                            stops: const [0.0, 0.3],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -30),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF121212),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (AdService().shouldShowAds) ...[
                          Center(child: AdService().getMediumRectangleAdWidget()),
                          const SizedBox(height: 32), // Clear gap between Ad and User Profile info
                        ],
                        // Name and Status
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(child: Text(_name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5))),
                                    if (_isVerified) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 22),
                                    ],
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.location_on_rounded, color: Colors.orangeAccent, size: 14),
                                    const SizedBox(width: 4),
                                    Text(locationDisplay, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13, fontWeight: FontWeight.w500)),
                                  ]),
                                ],
                              ),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: PresenceManager().getStatusNotifier(widget.phone, widget.isOnline),
                              builder: (context, isOnline, _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05), 
                                    borderRadius: BorderRadius.circular(20), 
                                    border: Border.all(color: isOnline ? Colors.green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1))
                                  ),
                                  child: Row(children: [
                                    CircleAvatar(backgroundColor: isOnline ? Colors.greenAccent : Colors.white24, radius: 3), 
                                    const SizedBox(width: 6), 
                                    Text(isOnline ? 'Online' : 'Offline', style: TextStyle(color: isOnline ? Colors.greenAccent : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))
                                  ]),
                                );
                              }
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),

                        // Detail Chips - Text Only
                        if (_isLoading)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(color: Colors.orangeAccent),
                          ))
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildTextDetail('Age', '$_age'),
                                _buildVerticalDivider(),
                                _buildTextDetail('Position', _position),
                                _buildVerticalDivider(),
                                _buildTextDetail('Place', _havePlace),
                              ],
                            ),
                          ),

                        const SizedBox(height: 32),
                        
                        // About Me - Location based
                        const Text('ABOUT ME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 1.2)),
                        const SizedBox(height: 12),
                        Text(
                          'Hi मैं $_name हूँ। मैं ${_city != "Unknown" ? _city : 'यहीं'} से हूँ और किसी ऐसे इंसान की तलाश में हूँ जिससे मैं mil saku.',
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6), height: 1.5)
                        ),

                        const SizedBox(height: 40),
                        
                        // Like Count Header (Psychological Trigger)
                        Row(
                          children: [
                            const Text('🔥 ', style: TextStyle(fontSize: 16)),
                            Text(
                              '${(_name.length * 7) % 50 + 5} people liked ${_name.toLowerCase()}', 
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // Reviews Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reviews by other users (${_reviews.length})', 
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, fontWeight: FontWeight.bold)
                              ),
                              const SizedBox(height: 16),
                              if (_reviews.isEmpty)
                                Text(
                                  'Abhi tak koi review nahi hai',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.1), fontSize: 12),
                                )
                              else
                                ..._reviews.map((r) => _buildReviewRow(r.reviewerName.toUpperCase(), r.comment, r.type)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Action Button
          if (widget.showMessageButton)
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: SafeArea(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.orange.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                    onTap: () {
                        if (AdService().shouldShowAds) {
                          AdService().showInterstitialAd(
                            onAdClosed: () {
                              ChatPage.navigate(
                                context,
                                name: _name,
                                receiverPhone: widget.phone,
                                distance: _distance,
                                position: _position,
                              );
                            }
                          );
                        } else {
                          ChatPage.navigate(
                            context,
                            name: _name,
                            receiverPhone: widget.phone,
                            distance: _distance,
                            position: _position,
                          );
                        }
                      },
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_rounded, color: Colors.black, size: 20),
                            SizedBox(width: 12),
                            Text('START CHAT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextDetail(String label, String value) {
    return Column(
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)),
      ],
    );
  }

  Widget _buildReviewRow(String name, String comment, String type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            type == 'good' ? Icons.sentiment_satisfied_alt_rounded : Icons.sentiment_very_dissatisfied_rounded,
            size: 14, 
            color: type == 'good' ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.redAccent.withValues(alpha: 0.5)
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, height: 1.3),
                children: [
                  TextSpan(text: '$name: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
                  TextSpan(text: comment, style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white.withValues(alpha: 0.05),
    );
  }
}
