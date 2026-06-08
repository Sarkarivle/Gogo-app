import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/guards/access_guard.dart';
import 'package:gogo/core/services/presence_manager.dart';
import 'package:gogo/core/services/typing_manager.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/profile/repositories/moderation_repository.dart';
import 'package:gogo/features/chat/screens/chat_screen.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => InboxScreenState();
}

class InboxScreenState extends State<InboxScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final List<dynamic> _chats = [];
  List<dynamic> _filteredChatsCache = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  Map<String, dynamic>? _currentUser;
  StreamSubscription? _socketEventSub;
  Timer? _inboxUpdateDebounce;

  // Filter States
  String _selectedDistance = 'Any';
  String _selectedAge = 'Any';
  bool _isOnlineOnly = false;
  String _havePlaceStatus = 'Any';
  final String _selectedPosition = 'Any';

  final ChatRepository _chatRepository = ChatRepository();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _initialize();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchInbox(loadMore: true);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _socketEventSub?.cancel();
    _inboxUpdateDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    _currentUser = UserRepository().currentUser;
    if (_currentUser != null) {
      _listenToSocketEvents();
      // Fast Cache Load
      _loadCachedInbox();
    }
    await _fetchInbox();
  }

  Future<void> _loadCachedInbox() async {
    if (_currentUser == null) return;
    final cachedData = await _chatRepository.getCachedInbox(_currentUser!['phone']);
    if (cachedData != null && mounted && _chats.isEmpty) {
      setState(() {
        final List<dynamic> fetchedChats = cachedData['chats'] ?? [];
        _prepareChats(fetchedChats);
        _chats.addAll(fetchedChats);
        _updateFilterCache();
      });
    }
  }

  // Unified data preparation to remove double code
  void _prepareChats(List<dynamic> fetchedChats) {
    for (var chat in fetchedChats) {
      chat['nPhone'] = PhoneUtils.normalize(chat['phone'] ?? '') ?? chat['phone'];
      String rawDist = (chat['distance'] ?? '').toString().replaceAll(' away', '').trim();
      if (rawDist.isEmpty && chat['calculated_dist'] != null) {
        rawDist = "${chat['calculated_dist']}km";
      }
      chat['dist_str'] = rawDist.isNotEmpty ? rawDist : '1km';
    }
  }

  // Public refresh method for parent access
  Future<void> refresh() async {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    await _fetchInbox();
  }

  void _listenToSocketEvents() {
    _socketEventSub = SocketService().eventStream.listen((event) {
      if (!mounted) return;
      _handleInboxUpdate(event['data'], event['event']);
    });
  }

  // Optimized local state management to eliminate redundant API calls
  bool _applyLocalUpdate(dynamic data, String eventName) {
    if (data == null || _currentUser == null) return false;

    final String myPhone = PhoneUtils.normalize(_currentUser!['phone']) ?? '';
    String? partnerPhone;

    // Logic to identify the partner's phone regardless of who is the sender
    if (data['phone'] != null) {
      partnerPhone = PhoneUtils.normalize(data['phone']);
    } else if (data['senderPhone'] != null || data['receiverPhone'] != null) {
      final s = PhoneUtils.normalize(data['senderPhone'] ?? '') ?? '';
      final r = PhoneUtils.normalize(data['receiverPhone'] ?? '') ?? '';
      partnerPhone = (s == myPhone) ? r : s;
    }

    if (partnerPhone == null || partnerPhone.isEmpty || partnerPhone == myPhone) return false;

    // Use nPhone for faster lookup if available
    int index = _chats.indexWhere((c) => (c['nPhone'] ?? PhoneUtils.normalize(c['phone'])) == partnerPhone);

    if (index == -1) return false; // New conversation requires full fetch for profile data

    setState(() {
      Map<String, dynamic> chatData = Map<String, dynamic>.from(_chats.removeAt(index));

      switch (eventName) {
        case 'user_deactivated':
          chatData['accountStatus'] = 'Deactivated';
          chatData['isDeactivated'] = true;
          break;
        case 'user_reactivated':
          chatData['accountStatus'] = 'Active';
          chatData['isDeactivated'] = false;
          break;
        case 'message_opened':
          if (PhoneUtils.normalize(data['receiverPhone'] ?? '') == myPhone) {
            chatData['unread'] = 0;
          }
          break;
        case 'unread_update':
          if (data['unreadCount'] != null) {
            chatData['unread'] = data['unreadCount'];
          }
          break;
        case 'receive_message':
        case 'conversation_update':
          final type = data['type'] ?? data['lastMessage']?['type'];
          final msg = data['message'] ?? data['lastMessage']?['message'];
          
          if (type == 'audio') {
            chatData['msg'] = '🎵 Voice Message';
          } else if (type == 'image') {
            chatData['msg'] = '📷 Image';
          } else if (type == 'video') {
            chatData['msg'] = '🎥 Video';
          } else if (msg != null) {
            chatData['msg'] = msg;
          }
          
          chatData['timestamp'] = data['timestamp'] ?? data['lastMessage']?['timestamp'] ?? DateTime.now().toIso8601String();

          if (data['unreadCount'] != null) {
            chatData['unread'] = data['unreadCount'];
          } else if (eventName == 'receive_message' && PhoneUtils.normalize(data['senderPhone'] ?? '') == partnerPhone) {
            chatData['unread'] = (chatData['unread'] ?? 0) + 1;
          }
          break;
      }

      _chats.insert(0, chatData);
      _updateFilterCache();
    });
    return true;
  }

  void _handleInboxUpdate(dynamic data, String? eventName) {
    if (!mounted || eventName == null) return;

    // Filter relevant events to avoid unnecessary processing
    const relevantEvents = {
      'receive_message', 'unread_update', 'conversation_update', 
      'message_opened', 'moderation_state_updated', 
      'user_deactivated', 'user_reactivated'
    };
    if (!relevantEvents.contains(eventName)) return;

    if (eventName == 'receive_message' && data?['senderPhone'] != null) {
      SocketService().setTyping(data['senderPhone'], false);
    }

    // Try handling locally first. Only fetch from API if chat is new or for critical state changes.
    bool localUpdateDone = _applyLocalUpdate(data, eventName);
    
    // Force a full fetch for moderation updates as they affect access permissions across the app
    if (!localUpdateDone || eventName == 'moderation_state_updated') {
      // Throttle rapid updates to prevent API spam
      if (_inboxUpdateDebounce?.isActive ?? false) _inboxUpdateDebounce!.cancel();
      _inboxUpdateDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _fetchInbox();
      });
    }
  }

  Future<void> _fetchInbox({bool loadMore = false}) async {
    if (_currentUser == null || !mounted) return;
    
    if (loadMore) {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      if (_isLoading) return;
      if (mounted && _chats.isEmpty) setState(() => _isLoading = true);
    }

    try {
      final data = await _chatRepository.getInbox(
        _currentUser!['phone'], 
        page: loadMore ? _currentPage + 1 : 1, 
        limit: 20
      );
      
      if (!mounted) return;
      
      List<dynamic> fetchedChats = data['chats'] ?? [];

      // Server already calculates 'distance' label with privacy and village/area logic.
      // We just ensure we have a fallback for the UI field name if needed.
      for (var chat in fetchedChats) {
        // Pre-normalize phone for faster lookups in the list
        chat['nPhone'] = PhoneUtils.normalize(chat['phone']) ?? chat['phone'];
        
        String rawDist = (chat['distance'] ?? '').toString().replaceAll(' away', '').trim();
        if (rawDist.isEmpty && chat['calculated_dist'] != null) {
          rawDist = "${chat['calculated_dist']}km";
        }
        chat['dist_str'] = rawDist.isNotEmpty ? rawDist : '1km';
      }

      if (mounted) {
        setState(() {
          _prepareChats(fetchedChats);
          if (loadMore) {
            _chats.addAll(fetchedChats);
            _currentPage++;
          } else {
            _chats.clear();
            _chats.addAll(fetchedChats);
            _currentPage = 1;
          }
          _hasMore = fetchedChats.length >= 20;
          _updateFilterCache();
        });
        
        _prefetchTopChats();
      }
    } catch (e) {
      debugPrint("Inbox Fetch Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _updateFilterCache() {
    // 1. Force sort the main list by timestamp to ensure "Newest First"
    _chats.sort((a, b) {
      final t1 = DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime(0);
      final t2 = DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime(0);
      return t2.compareTo(t1);
    });

    _filteredChatsCache = _chats.where((chat) {
      // Search Filter
      if (_searchQuery.isNotEmpty) {
        final name = (chat['name'] ?? '').toString().toLowerCase();
        if (!name.contains(_searchQuery.toLowerCase())) return false;
      }
      
      if (_isOnlineOnly) {
        if (!PresenceManager().isOnline(chat['phone'])) return false;
      }
      if (_selectedDistance != 'Any') {
        double maxDist = double.tryParse(_selectedDistance.replaceAll('km', '')) ?? 999.0;
        if ((chat['calculated_dist'] ?? 0.0) > maxDist) return false;
      }
      if (_selectedPosition != 'Any' && chat['pos'] != _selectedPosition) return false;
      return true;
    }).toList();
  }

  void _prefetchTopChats() {
    if (_currentUser == null) return;
    // Prefetch first 5 chats that have messages
    final chatsToPrefetch = _chats.take(5);
    for (var chat in chatsToPrefetch) {
      _chatRepository.prefetchHistory(_currentUser!['phone'], chat['phone']);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filteredChats = _filteredChatsCache;

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Deep Charcoal Background (Not exact black)
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1421), // Baingani Black
        elevation: 0,
        centerTitle: false,
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(hintText: "Search messages...", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none),
              onChanged: (v) => setState(() { _searchQuery = v; _updateFilterCache(); }),
            )
          : const Text("Messages", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: Colors.white, letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded, color: Colors.white54, size: 24),
            onPressed: () => setState(() { 
              _isSearching = !_isSearching; 
              if (!_isSearching) { _searchQuery = ''; _searchController.clear(); _updateFilterCache(); }
            }), 
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildFilterSection(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetchInbox(),
        color: Colors.orangeAccent.withValues(alpha: 0.7),
        backgroundColor: const Color(0xFF222222),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _buildFavouritesSection()),
            if (filteredChats.isNotEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 32, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    "RECENT CONVERSATIONS",
                    style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                  ),
                ),
              ),
            if (_isLoading && _chats.isEmpty)
              _buildSkeletonSliver()
            else if (filteredChats.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 60),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == filteredChats.length) {
                        return _buildSkeletonItem(); // Skeleton for Load More
                      }
                      final chat = filteredChats[index];
                      return Column(
                        children: [
                          _buildChatItem(chat, key: ValueKey(chat['phone'])),
                          if (index < filteredChats.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 84, right: 16),
                              child: Divider(color: Colors.white.withValues(alpha: 0.03), height: 1),
                            ),
                        ],
                      );
                    },
                    childCount: filteredChats.length + (_isLoadingMore ? 1 : 0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (c, i) => _buildSkeletonItem(),
          childCount: 8,
        ),
      ),
    );
  }

  Widget _buildSkeletonItem() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.04),
      highlightColor: Colors.white.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const CircleAvatar(radius: 28, backgroundColor: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 12, width: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1C1421), // Match AppBar
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildFilterChip('Distance: $_selectedDistance', () {
              _showFilterDialog('Distance Range', ['Any', '5km', '10km', '25km', '50km'], _selectedDistance, (v) {
                setState(() => _selectedDistance = v);
                _updateFilterCache();
              });
            }, isActive: _selectedDistance != 'Any'),
            _buildFilterChip('Age: $_selectedAge', () {
              _showFilterDialog('Age Selection', ['Any', '18-25', '26-35', '36+'], _selectedAge, (v) {
                setState(() => _selectedAge = v);
                _updateFilterCache();
              });
            }, isActive: _selectedAge != 'Any'),
            _buildFilterChip('Online', () {
              setState(() => _isOnlineOnly = !_isOnlineOnly);
              _updateFilterCache();
            }, isActive: _isOnlineOnly, isLive: _isOnlineOnly),
            _buildFilterChip('Room: $_havePlaceStatus', () {
              _showFilterDialog('Have Place?', ['Any', 'YES', 'NO'], _havePlaceStatus, (v) {
                setState(() => _havePlaceStatus = v);
                _updateFilterCache();
              });
            }, isActive: _havePlaceStatus != 'Any'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onTap, {bool isActive = false, bool isLive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.orangeAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.03)),
        ),
        child: Row(
          children: [
            if (isLive) ...[
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.orangeAccent : Colors.white54,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: isActive ? Colors.orangeAccent.withValues(alpha: 0.5) : Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildFavouritesSection() {
    final favourites = _chats.where((c) => c['isFavourite'] == true).toList();
    if (favourites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            "FAVOURITES",
            style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: favourites.length,
            itemBuilder: (context, index) {
              final chat = favourites[index];
              final bool isOnline = PresenceManager().getStatusNotifier(chat['phone'], chat['isOnline'] ?? false).value;

              return GestureDetector(
                onTap: () => _openChat(chat),
                onLongPress: () {
                   HapticFeedback.mediumImpact();
                   _showChatActions(chat);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isOnline ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
                                width: 1.5,
                              ),
                            ),
                            child: const CircleAvatar(
                              radius: 26,
                              backgroundColor: Color(0xFF222222),
                              child: Icon(Icons.person_rounded, color: Colors.white10, size: 30),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF0F0F0F), width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 60,
                        child: Text(
                          chat['name'],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openChat(dynamic chat) async {
    HapticFeedback.lightImpact();
    AccessGuard().runWithAccessCheck(
      context, 
      onAllowed: () async {
        if (!mounted) return;

        final partnerPhone = chat['phone'];
        
        // Optimistic UI: Clear unreads locally for instant feedback
        _setChatRead(partnerPhone);

        await ChatPage.navigate(
          context,
          name: chat['name'],
          receiverPhone: partnerPhone,
          distance: chat['dist_str'] ?? '',
          position: chat['position'] ?? chat['pos'] ?? '',
        );
        
        // Refresh local cache and UI on return to ensure order is correct 
        // without necessarily hitting the network if not needed.
        if (mounted) {
          setState(() {
            _updateFilterCache();
          });
        }
      }
    );
  }

  void _setChatRead(String phone) {
    final nPhone = PhoneUtils.normalize(phone);
    int index = _chats.indexWhere((c) => (c['nPhone'] ?? PhoneUtils.normalize(c['phone'])) == nPhone);
    if (index != -1 && (_chats[index]['unread'] ?? 0) > 0) {
      setState(() {
        _chats[index]['unread'] = 0;
        _updateFilterCache();
      });
    }
  }

  void _showChatActions(dynamic chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF222222), // Elevated black for modals
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                _buildActionTile(
                  icon: chat['isMuted'] == true ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                  title: chat['isMuted'] == true ? 'Turn On Notifications' : 'Turn Off Notifications',
                  onTap: () {
                    Navigator.pop(context);
                    _updateMeta(chat['phone'], isMuted: !(chat['isMuted'] == true));
                  },
                ),
                _buildActionTile(
                  icon: chat['isFavourite'] == true ? Icons.star_border_rounded : Icons.star_rounded,
                  title: chat['isFavourite'] == true ? 'Remove From Favourites' : 'Save As Favourites',
                  onTap: () {
                    Navigator.pop(context);
                    _updateMeta(chat['phone'], isFavourite: !(chat['isFavourite'] == true));
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: Colors.white10),
                ),
                _buildActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete From Chats',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteChat(chat);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? Colors.orangeAccent).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? Colors.orangeAccent, size: 20),
      ),
      title: Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  Future<void> _updateMeta(String partnerPhone, {bool? isMuted, bool? isFavourite, bool? isHidden}) async {
    if (_currentUser == null) return;

    // Live/Optimistic UI Update
    setState(() {
      final index = _chats.indexWhere((c) => c['phone'] == partnerPhone);
      if (index != -1) {
        if (isMuted != null) _chats[index]['isMuted'] = isMuted;
        if (isFavourite != null) _chats[index]['isFavourite'] = isFavourite;
        if (isHidden == true) _chats.removeAt(index);
        _updateFilterCache();
      }
    });

    final success = await _chatRepository.updateConversationMetadata(
      myPhone: _currentUser!['phone'],
      otherPhone: partnerPhone,
      isMuted: isMuted,
      isFavourite: isFavourite,
      isHidden: isHidden,
    );
    
    if (!success) {
      // Revert by fetching fresh data if server call failed
      _fetchInbox();
    }
  }

  void _confirmDeleteChat(dynamic chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text("Delete Chat?", style: TextStyle(color: Colors.white)),
        content: Text("This will remove the conversation with ${chat['name']} from your list.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _updateMeta(chat['phone'], isHidden: true);
            }, 
            child: const Text("DELETE", style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(dynamic chat, {Key? key}) {
    final String nPhone = chat['nPhone'] ?? PhoneUtils.normalize(chat['phone']) ?? '';
    
    return ValueListenableBuilder<bool>(
      key: key,
      valueListenable: PresenceManager().getStatusNotifier(nPhone, chat['isOnline'] ?? false),
      builder: (context, isOnline, _) {
        return TweenAnimationBuilder<double>(
          key: ValueKey("${chat['phone']}_${chat['timestamp']}"),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)), 
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    // Spotlight Effect: Halka glow jo animation ke saath fade hota hai
                    color: Colors.orangeAccent.withValues(alpha: 0.08 * (1 - value)),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.2 * (1 - value)),
                      width: 1,
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: InkWell(
            onTap: () => _openChat(chat),
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _showChatActions(chat);
            },
            borderRadius: BorderRadius.circular(20),
            child: ValueListenableBuilder<bool>(
              valueListenable: TypingManager().getTypingNotifier(nPhone),
              builder: (context, isTyping, _) {
                final bool isDeactivated = chat['accountStatus'] == 'Deactivated' || chat['isDeactivated'] == true;
                final int unreadCount = chat['unread'] ?? 0;

                return RepaintBoundary(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: unreadCount > 0 ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: unreadCount > 0 ? Colors.orangeAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.03),
                                  width: 1,
                                ),
                              ),
                              child: CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white.withValues(alpha: 0.03),
                              child: chat['profileImage'] != null 
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(28),
                                    child: CachedNetworkImage(
                                      imageUrl: ApiService.getSecureUrl(chat['profileImage']),
                                      fit: BoxFit.cover,
                                      memCacheWidth: 160,
                                      memCacheHeight: 160,
                                      placeholder: (c, u) => Icon(Icons.person_rounded, color: Colors.white.withValues(alpha: 0.08), size: 32),
                                    ),
                                  )
                                : Icon(Icons.person_rounded, color: Colors.white.withValues(alpha: 0.08), size: 32),
                            ),
                            ),
                            if (isOnline)
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF0F0F0F), width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat['name'],
                                      style: TextStyle(
                                        color: unreadCount > 0 ? Colors.white : Colors.white70,
                                        fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatTime(chat['timestamp']),
                                    style: TextStyle(
                                      color: unreadCount > 0 ? Colors.orangeAccent.withValues(alpha: 0.8) : Colors.white24,
                                      fontSize: 10,
                                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                chat['dist_str'],
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isDeactivated ? "Account Deactivated" : ((isTyping && !ModerationRepository().isBlocked(nPhone)) ? "typing..." : (chat['msg'] ?? '')),
                                      style: TextStyle(
                                        color: (isTyping && !ModerationRepository().isBlocked(nPhone)) ? Colors.greenAccent.withValues(alpha: 0.8) : (unreadCount > 0 ? Colors.white54 : Colors.white38),
                                        fontSize: 13,
                                        fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                        fontStyle: (isTyping && !ModerationRepository().isBlocked(nPhone)) ? FontStyle.italic : FontStyle.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.orangeAccent.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        unreadCount.toString(),
                                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final bool hasActiveFilters = _selectedDistance != 'Any' || _isOnlineOnly || _havePlaceStatus != 'Any' || _searchQuery.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasActiveFilters ? Icons.filter_list_off_rounded : Icons.chat_bubble_outline, 
            size: 60, 
            color: Colors.white.withValues(alpha: 0.05)
          ),
          const SizedBox(height: 24),
          Text(
            hasActiveFilters ? "No matches found" : "No messages yet",
            style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            hasActiveFilters 
              ? "Try adjusting your filters or search query to find conversations."
              : "When you start chatting with people, they will appear here.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedDistance = 'Any';
                  _selectedAge = 'Any';
                  _isOnlineOnly = false;
                  _havePlaceStatus = 'Any';
                  _searchQuery = '';
                  _searchController.clear();
                  _updateFilterCache();
                });
              },
              child: const Text("Clear All Filters", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
            if (_hasMore) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _fetchInbox(loadMore: true),
                child: const Text("Search in older messages", style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      DateTime date = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        return DateFormat('h:mm a').format(date);
      }
      if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
        return "Yesterday";
      }
      return DateFormat('d MMM').format(date);
    } catch (_) {
      return '';
    }
  }

  void _showFilterDialog(String title, List<String> options, String current, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF222222),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                ...options.map((opt) => ListTile(
                  title: Text(opt, style: TextStyle(color: opt == current ? Colors.orangeAccent : Colors.white, fontWeight: opt == current ? FontWeight.bold : FontWeight.normal)),
                  trailing: opt == current ? const Icon(Icons.check_circle_rounded, color: Colors.orangeAccent, size: 20) : null,
                  onTap: () { onSelect(opt); Navigator.pop(context); },
                )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
