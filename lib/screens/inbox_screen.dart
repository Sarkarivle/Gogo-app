import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';
import '../services/chat_repository.dart';
import '../services/premium_service.dart';
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final List<dynamic> _chats = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _currentUser;
  StreamSubscription? _socketEventSub;
  Position? _myPos;
  Timer? _inboxUpdateDebounce;

  // Filter States
  String _selectedDistance = 'Any';
  String _selectedAge = 'Any';
  bool _isOnlineOnly = false;
  String _havePlaceStatus = 'Any';
  String _selectedPosition = 'Any';

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
    _socketEventSub?.cancel();
    _inboxUpdateDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      _currentUser = jsonDecode(userData);
      _listenToSocketEvents();
    }
    await _getCurrentLocation();
    _fetchInbox();
  }

  Future<void> _getCurrentLocation() async {
    try {
      _myPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
    } catch (_) {}
  }

  void _listenToSocketEvents() {
    _socketEventSub = SocketService().eventStream.listen((event) {
      if (!mounted) return;
      
      final eventName = event['event'];
      final data = event['data'];

      if (eventName == 'receive_message' || eventName == 'unread_update' || eventName == 'message_opened') {
        _handleInboxUpdate(data);
      }
    });
  }

  // Optimize: Debounce inbox refresh to avoid spamming API on rapid messages
  void _handleInboxUpdate(dynamic data) {
    if (_inboxUpdateDebounce?.isActive ?? false) return;
    _inboxUpdateDebounce = Timer(const Duration(seconds: 3), () {
      if (mounted) _fetchInbox();
    });
  }

  Future<void> _fetchInbox({bool loadMore = false}) async {
    if (_currentUser == null) return;
    
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
      
      List<dynamic> fetchedChats = data['chats'] ?? [];

      if (_myPos != null) {
        for (var chat in fetchedChats) {
          if (chat['lat'] != null && chat['lng'] != null) {
            double dist = Geolocator.distanceBetween(
                _myPos!.latitude, _myPos!.longitude, 
                chat['lat'], chat['lng']) / 1000;
            chat['calculated_dist'] = dist;
            chat['dist_str'] = "${dist.toStringAsFixed(2)} km";
          } else {
            chat['dist_str'] = "Unknown";
          }
        }
      }

      if (mounted) {
        setState(() {
          if (loadMore) {
            _chats.addAll(fetchedChats);
            _currentPage++;
          } else {
            _chats.clear();
            _chats.addAll(fetchedChats);
            _currentPage = 1;
          }
          _hasMore = fetchedChats.length >= 20;
        });
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

  List<dynamic> _getFilteredChats() {
    return _chats.where((chat) {
      if (_isOnlineOnly) {
        bool isOnline = SocketService().onlineUsers.value[chat['phone']] ?? chat['isOnline'] ?? false;
        if (!isOnline) return false;
      }
      if (_selectedDistance != 'Any') {
        double maxDist = double.tryParse(_selectedDistance.replaceAll('km', '')) ?? 999.0;
        if ((chat['calculated_dist'] ?? 0.0) > maxDist) return false;
      }
      if (_selectedPosition != 'Any' && chat['pos'] != _selectedPosition) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats = _getFilteredChats();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17),
        elevation: 0,
        title: const Text("Inbox", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetchInbox(),
        color: Colors.orangeAccent,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterSection(),
              _buildFavouritesSection(),
              const Divider(color: Colors.white10, height: 1),
              if (_isLoading && _chats.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)))
              else if (filteredChats.isEmpty)
                _buildEmptyState()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredChats.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    if (index == filteredChats.length) {
                      return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)));
                    }
                    return _buildChatItem(filteredChats[index]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      color: const Color(0xFF2A0D17),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        children: [
          _buildFilterChip('Distance', _selectedDistance, () {
            _showFilterDialog('Distance Range', ['Any', '5km', '10km', '25km', '50km'], _selectedDistance, (v) => setState(() => _selectedDistance = v));
          }),
          _buildFilterChip('Age', _selectedAge, () {
            _showFilterDialog('Age Selection', ['Any', '18-25', '26-35', '36+'], _selectedAge, (v) => setState(() => _selectedAge = v));
          }),
          _buildFilterChip('Online', _isOnlineOnly ? 'Yes' : 'Any', () {
            setState(() => _isOnlineOnly = !_isOnlineOnly);
          }, isActive: _isOnlineOnly),
          _buildFilterChip('Kamra hai', _havePlaceStatus, () {
            _showFilterDialog('Have Place?', ['Any', 'YES', 'NO'], _havePlaceStatus, (v) => setState(() => _havePlaceStatus = v));
          }),
          _buildFilterChip('Position', _selectedPosition, () {
            _showFilterDialog('Position', ['Any', 'Top', 'Bottom', 'Versatile'], _selectedPosition, (v) => setState(() => _selectedPosition = v));
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500)),
            if (value != 'Any') ...[
              const SizedBox(width: 4),
              Text(value, style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _buildFavouritesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Icon(Icons.star, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 8),
              Text("Favourites", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 2, // Dummy count
            itemBuilder: (context, index) {
              return Container(
                width: 170,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(child: Text("maurya ji", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(index == 0 ? "21.40 km" : "15.0 km", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Top", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(index == 0 ? "Online" : "", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildChatItem(dynamic chat) {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: SocketService().onlineUsers,
      builder: (context, onlineMap, _) {
        return ValueListenableBuilder<Map<String, bool>>(
          valueListenable: SocketService().typingUsers,
          builder: (context, typingMap, _) {
            final bool isOnline = onlineMap[chat['phone']] ?? chat['isOnline'] ?? false;
            final bool isTyping = typingMap[chat['phone']] ?? false;

            return ListTile(
              onTap: () async {
                final isPremium = await PremiumService().checkPremiumAndRedirect(context);
                if (!isPremium) return;

                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(
                  builder: (c) => ChatPage(
                    name: chat['name'], 
                    receiverPhone: chat['phone'], 
                    distance: chat['dist_str'] ?? '', 
                    position: chat['pos'] ?? ''
                  )
                ));
                _fetchInbox();
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.grey, size: 35),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text("${chat['name']}, ${chat['pos'] ?? ''}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(_formatTime(chat['timestamp']), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(chat['dist_str'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (isOnline) ...[
                        const Text(" • ", style: TextStyle(color: Colors.white38)),
                        const Text("Online", style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ]
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isTyping ? "typing..." : (chat['msg'] ?? ''),
                    style: TextStyle(
                      color: isTyping ? Colors.greenAccent : Colors.white60,
                      fontSize: 14,
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 16),
          const Text("No messages yet", style: TextStyle(color: Colors.white38, fontSize: 15)),
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(color: Colors.white10),
            ...options.map((opt) => ListTile(
              title: Text(opt, style: TextStyle(color: opt == current ? Colors.orangeAccent : Colors.white)),
              trailing: opt == current ? const Icon(Icons.check, color: Colors.orangeAccent) : null,
              onTap: () { onSelect(opt); Navigator.pop(context); },
            )),
          ],
        ),
      ),
    );
  }
}
