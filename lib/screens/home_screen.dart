import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';
import '../services/profile_repository.dart';
import '../widgets/profile_card.dart';
import '../widgets/blinking_dot.dart';
import 'inbox_screen.dart';
import 'my_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  List<dynamic> _profiles = [];
  bool _isLoadingProfiles = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  Position? _lastKnownPosition;

  int _totalUnreadCount = 0;
  Map<String, dynamic>? currentUser;
  Timer? _unreadTimer;
  StreamSubscription? _socketEventSub;

  String _selectedDistance = '20km';
  String _selectedAge = 'Any';
  bool _isOnlineOnly = false;
  String _havePlaceStatus = 'Any';
  String _selectedPosition = 'Top, Ver';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _scrollController.addListener(_scrollListener);
    _initHomeScreen();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      final tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
      final cached = ProfileRepository.getCachedProfiles(tabName);
      
      setState(() {
        _profiles = cached != null ? List.from(cached) : [];
        _currentPage = 1;
        _hasMore = true;
        _isLoadingProfiles = _profiles.isEmpty;
      });
      
      _fetchProfiles();
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      if (!_isLoadingProfiles && !_isLoadingMore && _hasMore) {
        _fetchProfiles(loadMore: true);
      }
    }
  }

  void _resetAndFetch() {
    final tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
    final cached = ProfileRepository.getCachedProfiles(tabName);
    
    setState(() {
      if (cached != null) {
        _profiles = List.from(cached);
      } else {
        _profiles = [];
      }
      _currentPage = 1;
      _hasMore = true;
      _isLoadingProfiles = _profiles.isEmpty;
    });
    _fetchProfiles();
  }

  Future<void> _initHomeScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      currentUser = jsonDecode(userData);
      SocketService().updateCurrentUser(currentUser!['phone']);
    }
    _listenToSocketEvents();
    
    _fetchUnreadCount();
    _unreadTimer = Timer.periodic(const Duration(seconds: 10), (t) => _fetchUnreadCount());

    _loadInitialData();

    _updateMyLocation().then((_) {
      _fetchProfiles();
    });
  }

  void _loadInitialData() {
    final tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
    final cached = ProfileRepository.getCachedProfiles(tabName);
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _profiles = List.from(cached);
        _isLoadingProfiles = false;
      });
    } else {
      _fetchProfiles();
    }
  }

  void _listenToSocketEvents() {
    _socketEventSub = SocketService().eventStream.listen((event) {
      if (event['event'] == 'unread_update') {
        final data = event['data'];
        if (currentUser != null && data['phone'] == currentUser!['phone']) {
          _fetchUnreadCount();
        }
      }
    });
  }

  Future<void> _fetchUnreadCount() async {
    try {
      if (currentUser == null) {
        final prefs = await SharedPreferences.getInstance();
        final userData = prefs.getString('user_data');
        if (userData != null) currentUser = jsonDecode(userData);
      }
      if (currentUser == null) return;
      final response = await http.get(Uri.parse('http://72.61.170.181:5000/api/chat/inbox/${currentUser!['phone']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => _totalUnreadCount = data['totalUnread'] ?? 0);
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _updateMyLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        _lastKnownPosition = pos;
        
        String city = 'Unknown';
        String area = 'Unknown';
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            area = place.subLocality ?? place.thoroughfare ?? place.name ?? 'Unknown';
            city = place.locality ?? place.subAdministrativeArea ?? 'Unknown';
          }
        } catch (e) { debugPrint('Geocoding error: $e'); }

        if (currentUser != null) {
          await http.post(
            Uri.parse('http://72.61.170.181:5000/api/user/update-location'), 
            headers: {'Content-Type': 'application/json'}, 
            body: jsonEncode({
              'phone': currentUser!['phone'], 
              'lat': pos.latitude, 
              'lng': pos.longitude,
              'city': city,
              'area': area
            })
          );

          final prefs = await SharedPreferences.getInstance();
          Map<String, dynamic> updatedUser = Map.from(currentUser!);
          updatedUser['city'] = city;
          updatedUser['area'] = area;
          updatedUser['lat'] = pos.latitude;
          updatedUser['lng'] = pos.longitude;
          await prefs.setString('user_data', jsonEncode(updatedUser));
          if (mounted) setState(() => currentUser = updatedUser);
        }
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _fetchProfiles({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      final tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
      final cached = ProfileRepository.getCachedProfiles(tabName);
      
      if (mounted) {
        setState(() {
          if (cached != null && cached.isNotEmpty && _profiles.isEmpty) {
            _profiles = List.from(cached);
          }
          _isLoadingProfiles = _profiles.isEmpty;
        });
      }
    }

    try {
      final String tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
      Position? myPos = _lastKnownPosition;
      if (myPos == null) {
        try { myPos = await Geolocator.getLastKnownPosition(); } catch (_) {}
      }

      final newProfiles = await ProfileRepository.getDiscoverProfiles(
        myPhone: currentUser?['phone'] ?? '',
        page: loadMore ? _currentPage + 1 : 1,
        tab: tabName,
        distance: tabName == 'Nearby' ? _selectedDistance : null,
        age: _selectedAge,
        isOnlineOnly: tabName == 'Online' ? true : _isOnlineOnly,
        havePlace: _havePlaceStatus,
        position: _selectedPosition,
        lat: myPos?.latitude,
        lng: myPos?.longitude,
      );

      if (mounted) {
        setState(() {
          _isLoadingProfiles = false;
          _isLoadingMore = false;
          
          List<dynamic> processedProfiles = [];

          // App-side fine-tuned distance filtering for 'Nearby'
          if (tabName == 'Nearby' && _selectedDistance != 'Any' && myPos != null) {
            final maxKm = double.tryParse(_selectedDistance.replaceAll('km', '')) ?? 20.0;
            processedProfiles = newProfiles.where((p) {
              if (p['lat'] == null || p['lng'] == null) return false;
              double d = Geolocator.distanceBetween(myPos!.latitude, myPos!.longitude, p['lat'], p['lng']) / 1000;
              p['calculated_dist'] = "${d.toStringAsFixed(1)} km";
              return d <= maxKm;
            }).toList();
          } else {
            processedProfiles = newProfiles;
            for (var p in processedProfiles) {
              if (myPos != null && p['lat'] != null && p['lng'] != null) {
                double d = Geolocator.distanceBetween(myPos.latitude, myPos.longitude, p['lat'], p['lng']) / 1000;
                p['calculated_dist'] = "${d.toStringAsFixed(1)} km";
              } else if (p['calculated_dist'] == null) {
                p['calculated_dist'] = "Unknown";
              }
            }
          }

          if (loadMore) {
            if (processedProfiles.isEmpty) {
              _hasMore = false;
            } else {
              final existingPhones = _profiles.map((p) => p['phone']).toSet();
              final filteredNew = processedProfiles.where((p) => !existingPhones.contains(p['phone'])).toList();
              _profiles.addAll(filteredNew);
              _currentPage++;
              _hasMore = newProfiles.length >= 20;
            }
          } else {
            _profiles = processedProfiles;
            _currentPage = 1;
            _hasMore = newProfiles.length >= 20;
          }
        });
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoadingProfiles = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() { 
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose(); 
    _unreadTimer?.cancel(); 
    _socketEventSub?.cancel();
    _scrollController.dispose();
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withOpacity(0.05)))),
          _selectedIndex == 0 ? _buildHomeContent() : (_selectedIndex == 1 ? const InboxScreen() : const MyProfileScreen()),
          if (_selectedIndex == 0) Positioned(bottom: 30, left: 30, right: 30, child: _buildLiveButton()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildLiveButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFF4B2B), Color(0xFFFF416C), Color(0xFF8E2DE2)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(30), onTap: () {}, child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.videocam_rounded, color: Colors.white, size: 28), SizedBox(width: 12), Text('Start Live Video', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5))])),
      ),
    );
  }

  Widget _buildHomeContent() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(statusBarColor: Color(0xFF2A0D17), statusBarIconBrightness: Brightness.light),
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        toolbarHeight: 120,
        title: Column(children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _buildFilterChip('Distance: $_selectedDistance', true, onTap: () { _showFilterDialog('Distance Range', ['1km', '5km', '10km', '20km', '50km', '100km+'], _selectedDistance, (val) { setState(() => _selectedDistance = val); _resetAndFetch(); }); }),
            _buildFilterChip('Age: $_selectedAge', true, onTap: () { _showFilterDialog('Age Selection', ['Any', '18-25', '26-35', '36-45', '46+'], _selectedAge, (val) { setState(() => _selectedAge = val); _resetAndFetch(); }); }),
            _buildFilterChip(_isOnlineOnly ? 'Online Now' : 'Online', true, isLive: _isOnlineOnly, onTap: () { setState(() => _isOnlineOnly = !_isOnlineOnly); _resetAndFetch(); }),
            _buildFilterChip('Place: $_havePlaceStatus', true, onTap: () { _showFilterDialog('Have Place?', ['Any', 'YES', 'NO'], _havePlaceStatus, (val) { setState(() => _havePlaceStatus = val); _resetAndFetch(); }); }),
            _buildFilterChip('Pos: $_selectedPosition', false, onTap: () { _showFilterDialog('Position', ['Top', 'Bottom', 'Versatile', 'Top, Ver'], _selectedPosition, (val) { setState(() => _selectedPosition = val); _resetAndFetch(); }); }),
          ])),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Colors.orangeAccent,
            indicatorWeight: 3,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            dividerColor: Colors.transparent,
            tabs: [
              const Tab(text: 'Nearby'),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Online'), const SizedBox(width: 8), const BlinkingDot()])),
              const Tab(text: 'New'),
              const Tab(text: 'Popular'),
            ],
          ),
        ]),
        actions: [Padding(padding: const EdgeInsets.only(bottom: 50.0), child: IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white70), onPressed: () {}))],
      ),
      body: TabBarView(
        controller: _tabController, 
        physics: const NeverScrollableScrollPhysics(), // Disables left-right slide
        children: [_buildProfileGrid(), _buildProfileGrid(), _buildProfileGrid(), _buildProfileGrid()]
      ),
    );
  }

  void _showFilterDialog(String title, List<String> options, String currentValue, Function(String) onSelect) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: FadeTransition(
              opacity: anim1,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E).withOpacity(0.9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: const BorderSide(color: Colors.white10)),
                title: Column(children: [Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), const SizedBox(height: 20), Text(title, style: const TextStyle(color: Colors.orangeAccent, fontSize: 20, fontWeight: FontWeight.w800))]),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final bool isSelected = option == currentValue;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () { onSelect(option); Navigator.pop(context); },
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.orangeAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: isSelected ? Colors.orangeAccent.withOpacity(0.3) : Colors.transparent),
                              ),
                              child: Row(children: [
                                Text(option, style: TextStyle(color: isSelected ? Colors.orangeAccent : Colors.white, fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                const Spacer(),
                                if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.orangeAccent, size: 22),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool drop, {bool isLive = false, VoidCallback? onTap}) {
    return GestureDetector(onTap: onTap, child: Container(margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border.all(color: Colors.white.withOpacity(0.15)), borderRadius: BorderRadius.circular(12)), child: Row(children: [if (isLive) ...[const BlinkingDot(), const SizedBox(width: 8)], Text(label, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)), if (drop) ...[const SizedBox(width: 4), const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white70)]])));
  }

  Widget _buildProfileGrid() {
    return RefreshIndicator(
      onRefresh: () async => _resetAndFetch(),
      color: Colors.orangeAccent,
      backgroundColor: const Color(0xFF1E1E1E),
      child: Stack(
        children: [
          _profiles.isEmpty && !_isLoadingProfiles
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 100),
                    Center(
                      child: Column(
                        children: [
                          const Icon(Icons.person_search_rounded, size: 64, color: Colors.white10),
                          const SizedBox(height: 16),
                          const Text('No profiles found nearby', style: TextStyle(color: Colors.white54)),
                          TextButton(onPressed: _resetAndFetch, child: const Text('Try Again', style: TextStyle(color: Colors.orangeAccent)))
                        ],
                      ),
                    )
                  ],
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _profiles.length + (_isLoadingMore ? 2 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _profiles.length) {
                      return Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(20)),
                        child: const Center(child: CircularProgressIndicator(color: Colors.orangeAccent, strokeWidth: 2)),
                      );
                    }

                    final p = _profiles[i];
                    return ValueListenableBuilder<Map<String, bool>>(
                      valueListenable: SocketService().onlineUsers,
                      builder: (context, onlineMap, _) {
                        final bool isOnline = onlineMap[p['phone']] ?? p['isOnline'] ?? false;
                        return ProfileCard(
                          distance: p['calculated_dist'] ?? 'Unknown',
                          city: p['city'] ?? '',
                          area: p['area'] ?? '',
                          name: p['name'] ?? 'Unknown',
                          phone: p['phone'] ?? '',
                          nameColor: const Color(0xFFC69C55),
                          age: p['age'] ?? 20,
                          position: p['position'] ?? 'Top',
                          havePlace: p['havePlace'] ?? 'NO',
                          isVerified: p['isVerified'] ?? false,
                          isOnline: isOnline,
                          likedBy: (i + 1) * 12,
                        );
                      },
                    );
                  },
                ),
          if (_isLoadingProfiles)
            const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5))),
      child: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F0F0F),
        selectedItemColor: Colors.orangeAccent,
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (i) { setState(() => _selectedIndex = i); _fetchUnreadCount(); },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined, size: 28), activeIcon: Icon(Icons.explore, size: 28), label: 'Match'),
          BottomNavigationBarItem(icon: _totalUnreadCount > 0 ? Badge(backgroundColor: Colors.redAccent, label: Text(_totalUnreadCount.toString()), child: const Icon(Icons.chat_bubble_outline_rounded, size: 26)) : const Icon(Icons.chat_bubble_outline_rounded, size: 26), activeIcon: const Icon(Icons.chat_bubble_rounded, size: 26), label: 'Inbox'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded, size: 28), activeIcon: Icon(Icons.person_rounded, size: 28), label: 'Profile'),
        ],
      ),
    );
  }
}
