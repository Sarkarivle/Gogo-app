import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<dynamic> chatData = [];
  bool _isLoading = false;
  late IO.Socket socket;
  Map<String, dynamic>? currentUser;
  final Map<String, bool> _typingUsers = {};

  @override
  void initState() {
    super.initState();
    _initInbox();
  }

  Future<void> _initInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      currentUser = jsonDecode(userData);
      _initSocket();
    }
    _fetchInbox();
  }

  void _initSocket() {
    socket = IO.io('http://72.61.170.181:5000', <String, dynamic>{'transports': ['websocket'], 'autoConnect': true});
    socket.onConnect((_) {
      if (currentUser != null) {
        socket.emit('set_online', currentUser!['phone']);
      }
    });
    
    socket.on('user_status_change', (data) {
      if (mounted) {
        setState(() {
          for (var chat in chatData) {
            if (chat['phone'] == data['phone']) {
              chat['isOnline'] = data['isOnline'];
            }
          }
        });
      }
    });

    socket.on('display_typing', (data) {
      if (mounted) {
        setState(() {
          _typingUsers[data['phone']] = true;
        });
      }
    });

    socket.on('hide_typing', (data) {
      if (mounted) {
        setState(() {
          _typingUsers[data['phone']] = false;
        });
      }
    });
    
    socket.on('unread_update', (data) {
       if (currentUser != null && data['phone'] == currentUser!['phone']) _fetchInbox();
    });
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Future<void> _fetchInbox() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = jsonDecode(prefs.getString('user_data')!);
      Position? myPos;
      try { myPos = await Geolocator.getCurrentPosition(); } catch (_) {}
      final response = await http.get(Uri.parse('http://72.61.170.181:5000/api/inbox/${user['phone']}'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> data = decoded['chats'] ?? [];
        if (myPos != null) {
          for (var chat in data) {
            if (chat['lat'] != null && chat['lng'] != null) {
              double dist = Geolocator.distanceBetween(myPos.latitude, myPos.longitude, chat['lat'], chat['lng']) / 1000;
              chat['dist'] = "${dist.toStringAsFixed(1)} km";
            }
          }
        }
        if (mounted) setState(() => chatData = data);
      }
    } catch (e) { print(e); } finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showLongPressMenu(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2A0D17),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 15),
              Text(chatData[index]['name'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white10),
              _buildPopupItem("Turn off notifications", Icons.notifications_off_outlined),
              _buildPopupItem("Delete from chats", Icons.delete_sweep_rounded, isDelete: true, onTap: () {
                setState(() { chatData.removeAt(index); });
                Navigator.pop(context);
              }),
              _buildPopupItem("Save as Favourites", Icons.star_border_rounded),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupItem(String text, IconData icon, {bool isDelete = false, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap ?? () => Navigator.pop(context),
      leading: Icon(icon, color: isDelete ? Colors.redAccent : Colors.orangeAccent, size: 22),
      title: Text(text, style: TextStyle(color: isDelete ? Colors.redAccent : Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w500)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(backgroundColor: const Color(0xFF2A0D17), elevation: 0, title: const Text("Inbox", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))),
      body: RefreshIndicator(
        onRefresh: _fetchInbox,
        color: Colors.orangeAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        child: Column(children: [
          Container(
            color: const Color(0xFF2A0D17),
            padding: const EdgeInsets.only(bottom: 15),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
              _buildInboxFilter("Distance"), _buildInboxFilter("Age"), _buildInboxFilter("Online"), _buildInboxFilter("Kamra hai"), _buildInboxFilter("Position")
            ])),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Icon(Icons.star, color: Colors.orangeAccent, size: 20), const SizedBox(width: 8), const Text("Favourites", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16))])),
                  SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
                    _buildFavCard("Karan", "Mumbai", "Top"), const SizedBox(width: 12), _buildFavCard("Sachin", "Delhi", "Bottom")
                  ])),
                  const SizedBox(height: 20), const Divider(color: Colors.white10, height: 1),
                  if (_isLoading && chatData.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Colors.orangeAccent)))
                  else ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: chatData.length,
                    separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) {
                      final chat = chatData[i];
                      final bool isTyping = _typingUsers[chat['phone']] ?? false;
                      final bool isOnline = chat['isOnline'] ?? false;
                      
                      return ListTile(
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (c) => ChatPage(name: chat['name'] ?? chat['phone'], receiverPhone: chat['phone'], distance: chat['dist'] ?? '', position: chat['pos'] ?? '')));
                          _fetchInbox();
                        },
                        onLongPress: () => _showLongPressMenu(i),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Stack(
                          children: [
                            const CircleAvatar(radius: 28, backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white54, size: 30)),
                            if (isOnline) Positioned(right: 2, bottom: 2, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0F0F0F), width: 2)))),
                          ],
                        ),
                        title: Row(children: [
                          Expanded(child: Text("${chat['name']}, ${chat['pos'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(chat['time'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12))
                        ]),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 4), 
                          Row(
                            children: [
                              Text((chat['area'] != null && chat['area'] != "Unknown" && chat['area'] != "") ? "${chat['area']}, ${chat['dist'] ?? ''}" : (chat['city'] ?? chat['dist'] ?? ''), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              if (isOnline) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                                const SizedBox(width: 4),
                                const Text("Online", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold))
                              ]
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                      Expanded(
                        child: Text(
                          isTyping ? "typing..." : (chat['msg'] ?? ''), 
                          style: TextStyle(
                            color: isTyping ? Colors.greenAccent : Colors.white70, 
                            fontSize: 14, 
                            fontWeight: isTyping ? FontWeight.bold : FontWeight.normal,
                            fontStyle: isTyping ? FontStyle.italic : FontStyle.normal
                          ), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        )
                      ),
                            if ((chat['unread'] ?? 0) > 0) Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle), child: Text(chat['unread'].toString(), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)))
                          ]),
                        ]),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInboxFilter(String label) => Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(20)), child: Row(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)), const SizedBox(width: 4), const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white54)]));
  Widget _buildFavCard(String name, String dist, String pos) => Container(width: 160, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent)), Text(dist, style: const TextStyle(fontSize: 11, color: Colors.white70))]), const SizedBox(height: 8), Text(pos, style: const TextStyle(fontSize: 12, color: Colors.white70))]));
}
