import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gogo/core/location/location_service.dart';
import 'package:gogo/core/location/location_repository.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shimmer/shimmer.dart';

import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/services/presence_manager.dart';
import 'package:gogo/features/profile/repositories/profile_repository.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/profile/widgets/profile_card.dart';
import 'package:gogo/shared/widgets/blinking_dot.dart';
import 'package:gogo/features/home/widgets/home_filters.dart';
import 'package:gogo/features/chat/screens/inbox_screen.dart';
import 'package:gogo/features/profile/screens/my_profile_screen.dart';
import 'package:gogo/features/random_live/screens/random_live_intro_screen.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';

import 'package:gogo/core/guards/access_guard.dart';
import 'package:gogo/core/services/ad_service.dart';
import 'package:flutter/rendering.dart';

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
  bool _isLoadingProfiles = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isFooterVisible = ValueNotifier<bool>(true);
  Position? _lastKnownPosition;

  int _totalUnreadCount = 0;
  Map<String, dynamic>? currentUser;
  Timer? _unreadTimer;
  Timer? _unreadDebounce;
  StreamSubscription? _socketEventSub;
  
  // Professional Request Lifecycle Management
  int _lastRequestTimestamp = 0;
  bool _isRequestInProgress = false;

  String _selectedDistance = '300km';
  bool _isDistanceManuallySelected = false;
  String _selectedAge = 'Any';
  bool _isOnlineOnly = false;
  String _havePlaceStatus = 'Any';
  String _selectedPosition = 'Any';

  final UserRepository _userRepository = UserRepository();
  final ChatRepository _chatRepository = ChatRepository();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _scrollController.addListener(_scrollListener);
    UserRepository().userNotifier.addListener(_onUserUpdated);
    _initHomeScreen();
  }

  void _onUserUpdated() {
    if (!mounted) return;
    final newUser = UserRepository().currentUser;
    
    // Only trigger setState if premium status or essential info changed
    // This prevents lag during frequent location updates
    if (newUser?['isPremium'] != currentUser?['isPremium'] || 
        newUser?['name'] != currentUser?['name'] ||
        newUser?['accountStatus'] != currentUser?['accountStatus']) {
      setState(() {
        currentUser = newUser;
      });
    } else {
      currentUser = newUser; // Keep the reference updated without rebuild
    }
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      _resetAndFetch(forceLoading: true);
    }
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      if (_isFooterVisible.value) _isFooterVisible.value = false;
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
      if (!_isFooterVisible.value) _isFooterVisible.value = true;
    }

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

    // Clear ALL cache when filters change to ensure fresh data across all tabs
    ProfileRepository.clearCache();

    setState(() {
      _profiles = [];
      _currentPage = 1;
      _hasMore = true;
      _isLoadingProfiles = true;
    });
    
    // Ensure we don't hit the "is already loading" block by using a slight delay or resetting flag
    _isRequestInProgress = false;
    _fetchProfiles(isReset: true);
  }

  Future<void> _initHomeScreen() async {
    // 1. Background Tasks (Non-blocking)
    NotificationService.initialize();
    PremiumService().init();
    
    _listenToSocketEvents();
    _fetchUnreadCount();
    
    // Background unread sync every 30s
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (t) => _fetchUnreadCount());

    // 2. Profiles immediately + User sync in background
    _updateLocationAndProfiles();
    
    _userRepository.getCurrentUser().then((user) {
      if (user != null && mounted) {
        setState(() => currentUser = user);
        SocketService().updateCurrentUser(user['phone']);
      }
    });
  }

  // _loadInitialData is now integrated into _updateLocationAndProfiles to prevent double fetch

  Future<void> _updateLocationAndProfiles() async {
    // 1. Show cache immediately if available for instant feel
    if (mounted) {
      final tabName = ['Nearby', 'Online'][_tabController.index];
      final cached = ProfileRepository.getCachedProfiles(tabName);
      
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _profiles = List.from(cached);
          _isLoadingProfiles = false;
        });
      }
    }

    // 2. Always trigger fresh fetch immediately
    _fetchProfiles(isReset: true);
    
    // 3. Location update in background (Non-blocking)
    LocationService().getCurrentPosition().then((pos) {
      _lastKnownPosition = pos;
    });

    if (currentUser != null && mounted) {
      LocationRepository().updateLocation(currentUser!['phone']).then((_) async {
        final updatedUser = await _userRepository.getCurrentUser();
        if (mounted && updatedUser != null) {
          currentUser = updatedUser;
        }
      });
    }
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
      } else if (event['event'] == 'premium_status_refresh') {
        final data = event['data'];
        // FIX: Only show toast if a specific message is provided by the server
        if (mounted && data != null && data['message'] != null && data['message'].toString().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    data['type'] == 'warning' ? Icons.warning_amber_rounded : Icons.check_circle_outline, 
                    color: Colors.white
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(data['message'], style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              backgroundColor: data['type'] == 'warning' ? Colors.deepOrangeAccent : Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ),
          );
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

  Future<void> _fetchProfiles({bool loadMore = false, bool isReset = false}) async {
    final int requestTimestamp = DateTime.now().millisecondsSinceEpoch;
    
    if (loadMore) {
      if (_isLoadingMore || !_hasMore || _isRequestInProgress) return;
      setState(() => _isLoadingMore = true);
    } else {
      _lastRequestTimestamp = requestTimestamp;
      if (_profiles.isEmpty && !isReset) {
        setState(() => _isLoadingProfiles = true);
      }
    }

    _isRequestInProgress = true;

    try {
      final String tabName = ['Nearby', 'Online'][_tabController.index];
      const int limit = 10; // Professional small batch size
      
      List<dynamic> newProfiles = [];
      
      // Standard Fetch (Nearby or Online)
      newProfiles = await ProfileRepository.getDiscoverProfiles(
        myPhone: currentUser?['phone'] ?? '',
        page: loadMore ? _currentPage + 1 : 1,
        limit: limit,
        tab: tabName,
        distance: (tabName == 'Nearby' && _isDistanceManuallySelected) ? _selectedDistance : null,
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
            p['full_dist'] = (p['fullDistance'] ?? '').replaceAll(' away', '');
            
            // SYNC PRESENCE: Ensure the PresenceManager is aware of the latest status from API
            if (p['phone'] != null) {
              PresenceManager().updateStatus(p['phone'], p['isOnline'] ?? false);
            }
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
    UserRepository().userNotifier.removeListener(_onUserUpdated);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Background Glow
            Positioned(
              top: -100, 
              right: -100, 
              child: Container(
                width: 300, 
                height: 300, 
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  color: Colors.orange.withValues(alpha: 0.05)
                )
              )
            ),
          
            // Using IndexedStack for Instant & Smooth Tab Switching
            IndexedStack(
              index: _selectedIndex == 1 ? 2 : (_selectedIndex == 2 ? 1 : _selectedIndex),
              children: [
                _buildHomeContent(),
                const RandomLiveIntroScreen(),
                InboxScreen(key: _inboxKey),
                const MyProfileScreen(),
              ],
            ),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _isFooterVisible,
          builder: (context, visible, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedIndex == 0 && AdService().shouldShowAds)
                  AdService().getBannerAdWidget(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: visible ? null : 0,
                  child: Wrap( // Wrap to avoid overflow when height is 0
                    children: [if (visible) child!],
                  ),
                ),
              ],
            );
          },
          child: _buildBottomNav(),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final double topPadding = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        // Custom App Bar Area
        Container(
          padding: EdgeInsets.only(top: topPadding + 10, bottom: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF1C1421), // Dark Purple-ish Black (Baingani Black)
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal, 
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  HomeFilterChip(
                    label: _isDistanceManuallySelected ? 'Range: $_selectedDistance' : 'Distance',
                    onTap: () => FilterDialog.show(context, 'Distance Range', ['1km', '5km', '10km', '20km', '50km', '100km', '200km', '300km', '500km'], _selectedDistance, (val) { setState(() { _selectedDistance = val; _isDistanceManuallySelected = true; }); _resetAndFetch(); }),
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
                    onTap: () => FilterDialog.show(context, 'Position', ['Any', 'Top', 'Bottom', 'Versatile', 'Top, Ver'], _selectedPosition, (val) { setState(() => _selectedPosition = val); _resetAndFetch(); }),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              TabBar(
                controller: _tabController,
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                indicatorColor: Colors.orangeAccent,
                indicatorWeight: 3,
                labelColor: Colors.orangeAccent,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  const Tab(text: 'Nearby'),
                  Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Online'), const SizedBox(width: 8), const BlinkingDot()])),
                ],
              ),
            ],
          ),
        ),
        
        // Profiles Body
        Expanded(
          child: TabBarView(
            controller: _tabController, 
            physics: const NeverScrollableScrollPhysics(),
            children: [_buildProfileGrid(), _buildProfileGrid()]
          ),
        ),
      ],
    );
  }

  Widget _buildProfileGrid() {
    return RefreshIndicator(
      onRefresh: () async => _resetAndFetch(),
      color: Colors.orangeAccent,
      backgroundColor: const Color(0xFF222222),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), // More bottom padding for banner
                  cacheExtent: 1500,
                  addRepaintBoundaries: true,
                  addAutomaticKeepAlives: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _profiles.length + (AdService().shouldShowAds ? (_profiles.length ~/ 5) : 0) + (_isLoadingMore ? 2 : 0),
                  itemBuilder: (context, i) {
                    // Logic: Every 6th item is an ad (after 5 profiles)
                    bool isAd = AdService().shouldShowAds && (i + 1) % 6 == 0;
                    
                    if (isAd) {
                      return AdService().getNativeAdWidget();
                    }

                    // Calculate correct profile index by subtracting number of ads shown before this item
                    int profileIndex = AdService().shouldShowAds ? (i - (i ~/ 6)) : i;

                    if (profileIndex >= _profiles.length) {
                      return Shimmer.fromColors(
                        baseColor: Colors.white.withValues(alpha: 0.05),
                        highlightColor: Colors.white.withValues(alpha: 0.1),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        ),
                      );
                    }

                    final p = _profiles[profileIndex];
                    return RepaintBoundary(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: PresenceManager().getStatusNotifier(p['phone'], p['isOnline'] ?? false),
                        builder: (context, isOnline, _) {
                          return ProfileCard(
                            distance: p['calculated_dist'] ?? 'Unknown',
                            fullDistance: p['full_dist'],
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
                            hideFarDistance: true,
                          );
                        },
                      ),
                    );
                  },
                ),
          if (_isLoadingProfiles)
            _buildSkeletonGrid(),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5))),
      child: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.orangeAccent,
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (i) { 
          if (i == 2) { // Live Tab (Now at index 2)
            AccessGuard().runWithAccessCheck(
              context, 
              onAllowed: () {
                setState(() => _selectedIndex = i);
              }
            );
            return;
          }

          if (i == _selectedIndex) {
            // Already on this tab - Refresh it
            if (i == 0) {
              _resetAndFetch(); // Match Tab Refresh
            } else if (i == 1) { // Inbox Tab
              _inboxKey.currentState?.refresh(); 
            }
          } else {
            // Switching to a new tab
            setState(() => _selectedIndex = i);
            _fetchUnreadCount();
            
            // If switching TO Inbox, we also want it to refresh immediately
            if (i == 1) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted && _selectedIndex == 1) {
                  _inboxKey.currentState?.refresh();
                }
              });
            }
          }
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined, size: 28), activeIcon: Icon(Icons.explore, size: 28), label: 'Match'),
          BottomNavigationBarItem(icon: _totalUnreadCount > 0 ? Badge(backgroundColor: Colors.redAccent, label: Text(_totalUnreadCount.toString()), child: const Icon(Icons.chat_bubble_outline_rounded, size: 26)) : const Icon(Icons.chat_bubble_outline_rounded, size: 26), activeIcon: const Icon(Icons.chat_bubble_rounded, size: 26), label: 'Inbox'),
          const BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined, size: 28), activeIcon: Icon(Icons.videocam, size: 28), label: 'Live'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded, size: 28), activeIcon: Icon(Icons.person_rounded, size: 28), label: 'Profile'),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), 
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05))
        ),
        title: const Text("Exit GoGo?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to close the app?", style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("YES, EXIT", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
