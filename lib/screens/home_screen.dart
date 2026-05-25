import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/socket_service.dart';
import '../services/profile_repository.dart';
import '../services/user_repository.dart';
import '../services/chat_repository.dart';
import '../widgets/profile_card.dart';
import '../widgets/blinking_dot.dart';
import '../widgets/home_filters.dart';
import 'inbox_screen.dart';
import 'my_profile_screen.dart';
import '../randomLive/screens/random_live_intro_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  final GlobalKey<InboxScreenState> _inboxKey = GlobalKey<InboxScreenState>();
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
  Timer? _unreadDebounce;
  StreamSubscription? _socketEventSub;
  
  // Professional Request Lifecycle Management
  int _lastRequestTimestamp = 0;
  bool _isRequestInProgress = false;

  String _selectedDistance = '20km';
  String _selectedAge = 'Any';
  bool _isOnlineOnly = false;
  String _havePlaceStatus = 'Any';
  String _selectedPosition = 'Top, Ver';

  final UserRepository _userRepository = UserRepository();
  final ChatRepository _chatRepository = ChatRepository();

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
      _resetAndFetch(forceLoading: true);
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      if (!_isLoadingProfiles && !_isLoadingMore && _hasMore) {
        _fetchProfiles(loadMore: true);
      }
    }
  }

  void _resetAndFetch({bool forceLoading = false}) {
    // Scroll to top first
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }

    final tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
    
    // Clear relevant cache when filters change to ensure fresh data
    // Especially important for the "Nearby" tab which is highly filter-dependent
    if (tabName == 'Nearby') {
      ProfileRepository.clearCache();
    }

    final cached = ProfileRepository.getCachedProfiles(tabName);
    
    setState(() {
      if (cached != null && !forceLoading) {
        _profiles = List.from(cached);
      } else {
        _profiles = [];
      }
      _currentPage = 1;
      _hasMore = true;
      // We set this to true if we have no data to show, to trigger the spinner
      _isLoadingProfiles = _profiles.isEmpty;
    });
    
    // Ensure we don't hit the "is already loading" block by using a slight delay or resetting flag
    _isRequestInProgress = false;
    _fetchProfiles();
  }

  Future<void> _initHomeScreen() async {
    currentUser = await _userRepository.getCurrentUser();
    if (currentUser != null) {
      SocketService().updateCurrentUser(currentUser!['phone']);
    }
    
    _listenToSocketEvents();
    _fetchUnreadCount();
    
    // Background unread sync every 30s (backup for socket)
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (t) => _fetchUnreadCount());

    _loadInitialData();

    // Location & Profiles
    _updateLocationAndProfiles();
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

  Future<void> _updateLocationAndProfiles() async {
    if (currentUser != null && mounted) {
      try {
        await _userRepository.updateLocation(currentUser!['phone']);
        // After location update, refresh current user and profiles
        final updatedUser = await _userRepository.getCurrentUser();
        if (mounted && updatedUser != null) {
          setState(() {
            currentUser = updatedUser;
          });
        }
      } catch (e) {
        debugPrint("Location update error: $e");
      }
    }
    
    _lastKnownPosition ??= await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2), onTimeout: () => null);
    _lastKnownPosition ??= await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      ),
    );
    
    if (mounted) _fetchProfiles();
  }

  void _listenToSocketEvents() {
    _socketEventSub = SocketService().eventStream.listen((event) {
      if (!mounted) return;
      
      if (event['event'] == 'unread_update' || event['event'] == 'receive_message') {
        _fetchUnreadCount();
      } else if (event['event'] == 'user_deactivated') {
        final phone = event['data']['phone'];
        if (mounted) {
          setState(() {
            _profiles.removeWhere((p) => p['phone'] == phone);
          });
        }
      } else if (event['event'] == 'user_reactivated') {
        // We don't necessarily need to add them back instantly 
        // as they'll show up on next refresh/pagination, 
        // but it could be done if we wanted.
      }
    });
  }

  Future<void> _fetchUnreadCount() async {
    if (currentUser == null || !mounted) return;
    
    // Simple debounce to prevent multiple rapid API calls
    if (_unreadDebounce?.isActive ?? false) return;
    _unreadDebounce = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      try {
        final data = await _chatRepository.getInbox(currentUser!['phone'], limit: 1);
        if (mounted) {
          setState(() => _totalUnreadCount = data['totalUnread'] ?? 0);
        }
      } catch (e) {
        debugPrint("Unread count error: $e");
      }
    });
  }

  Future<void> _fetchProfiles({bool loadMore = false}) async {
    final int requestTimestamp = DateTime.now().millisecondsSinceEpoch;
    
    if (loadMore) {
      if (_isLoadingMore || !_hasMore || _isRequestInProgress) return;
      setState(() => _isLoadingMore = true);
    } else {
      _lastRequestTimestamp = requestTimestamp;
      if (_profiles.isEmpty) {
        setState(() => _isLoadingProfiles = true);
      }
    }

    _isRequestInProgress = true;

    try {
      final String tabName = ['Nearby', 'Online', 'New', 'Popular'][_tabController.index];
      const int limit = 10; // Professional small batch size
      
      final newProfiles = await ProfileRepository.getDiscoverProfiles(
        myPhone: currentUser?['phone'] ?? '',
        page: loadMore ? _currentPage + 1 : 1,
        limit: limit,
        tab: tabName,
        distance: tabName == 'Nearby' ? _selectedDistance : null,
        age: _selectedAge,
        isOnlineOnly: tabName == 'Online' ? true : _isOnlineOnly,
        havePlace: _havePlaceStatus,
        position: _selectedPosition,
        lat: _lastKnownPosition?.latitude,
        lng: _lastKnownPosition?.longitude,
      );

      if (!loadMore && requestTimestamp != _lastRequestTimestamp) {
        return;
      }

      if (mounted) {
        setState(() {
          _isLoadingProfiles = false;
          _isLoadingMore = false;
          
          List<dynamic> processedProfiles = List.from(newProfiles);
          
          // Server already calculates 'distance' label with privacy and village/area logic.
          // We use that directly instead of calculating it locally to ensure consistency.
          for (var p in processedProfiles) {
            p['calculated_dist'] = (p['distance'] ?? '').replaceAll(' away', '');
          }

          if (loadMore) {
            if (processedProfiles.isEmpty) {
              _hasMore = false;
            } else {
              // Deduplicate
              final existingPhones = _profiles.map((p) => p['phone']).toSet();
              final filteredNew = processedProfiles.where((p) => !existingPhones.contains(p['phone'])).toList();
              
              if (filteredNew.isEmpty && processedProfiles.isNotEmpty) {
                // If all new profiles were already in list (shouldn't happen with proper pagination), 
                // but we might want to still try next page or stop
                _hasMore = false; 
              } else {
                _profiles.addAll(filteredNew);
                _currentPage++;
                _hasMore = newProfiles.length >= limit;
              }
            }
          } else {
            _profiles = processedProfiles;
            _currentPage = 1;
            _hasMore = newProfiles.length >= limit;
          }
        });
      }
    } catch (e) {
      debugPrint('Discovery fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoadingProfiles = false;
          _isLoadingMore = false;
        });
      }
    } finally {
      if (requestTimestamp == _lastRequestTimestamp || loadMore) {
        _isRequestInProgress = false;
      }
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Random lifecycle handling is now encapsulated in RandomRoomService/randomLive module
  }

  @override
  void dispose() { 
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose(); 
    _unreadTimer?.cancel(); 
    _unreadDebounce?.cancel();
    _socketEventSub?.cancel();
    _scrollController.dispose();
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(top: -100, right: -100, child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withValues(alpha: 0.05)))),
          _selectedIndex == 0 ? _buildHomeContent() : (_selectedIndex == 1 ? InboxScreen(key: _inboxKey) : const MyProfileScreen()),
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
        boxShadow: [BoxShadow(color: Colors.purple.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30), 
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RandomLiveIntroScreen()),
            );
          }, 
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.videocam_rounded, color: Colors.white, size: 28), SizedBox(width: 12), Text('Start Live Video', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5))])
        ),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal, 
            child: Row(children: [
              HomeFilterChip(
                label: 'Distance: $_selectedDistance', 
                onTap: () => FilterDialog.show(context, 'Distance Range', ['1km', '5km', '10km', '20km', '50km', '100km+'], _selectedDistance, (val) { setState(() => _selectedDistance = val); _resetAndFetch(); }),
              ),
              HomeFilterChip(
                label: 'Age: $_selectedAge', 
                onTap: () => FilterDialog.show(context, 'Age Selection', ['Any', '18-25', '26-35', '36-45', '46+'], _selectedAge, (val) { setState(() => _selectedAge = val); _resetAndFetch(); }),
              ),
              HomeFilterChip(
                label: _isOnlineOnly ? 'Online Now' : 'Online', 
                isLive: _isOnlineOnly, 
                onTap: () { setState(() => _isOnlineOnly = !_isOnlineOnly); _resetAndFetch(); },
              ),
              HomeFilterChip(
                label: 'Place: $_havePlaceStatus', 
                onTap: () => FilterDialog.show(context, 'Have Place?', ['Any', 'YES', 'NO'], _havePlaceStatus, (val) { setState(() => _havePlaceStatus = val); _resetAndFetch(); }),
              ),
              HomeFilterChip(
                label: 'Pos: $_selectedPosition', 
                hasDropdown: false, 
                onTap: () => FilterDialog.show(context, 'Position', ['Top', 'Bottom', 'Versatile', 'Top, Ver'], _selectedPosition, (val) { setState(() => _selectedPosition = val); _resetAndFetch(); }),
              ),
            ]),
          ),
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _profiles.length + (_isLoadingMore ? 2 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _profiles.length) {
                      return Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20)),
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
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5))),
      child: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F0F0F),
        selectedItemColor: Colors.orangeAccent,
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (i) { 
          if (i == _selectedIndex) {
            // Already on this tab - Refresh it
            if (i == 0) {
              _resetAndFetch(); // Match Tab Refresh
            } else if (i == 1) {
              _inboxKey.currentState?.refresh(); // Inbox Tab Refresh
            }
          } else {
            // Switching to a new tab
            setState(() => _selectedIndex = i);
            _fetchUnreadCount();
            
            // If switching TO Inbox, we also want it to refresh immediately
            if (i == 1) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _inboxKey.currentState?.refresh();
              });
            }
          }
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined, size: 28), activeIcon: Icon(Icons.explore, size: 28), label: 'Match'),
          BottomNavigationBarItem(icon: _totalUnreadCount > 0 ? Badge(backgroundColor: Colors.redAccent, label: Text(_totalUnreadCount.toString()), child: const Icon(Icons.chat_bubble_outline_rounded, size: 26)) : const Icon(Icons.chat_bubble_outline_rounded, size: 26), activeIcon: const Icon(Icons.chat_bubble_rounded, size: 26), label: 'Inbox'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded, size: 28), activeIcon: Icon(Icons.person_rounded, size: 28), label: 'Profile'),
        ],
      ),
    );
  }
}
