import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import 'chat_settings_screen.dart';
import 'profile_detail_screen.dart';

class ChatPage extends StatefulWidget {
  final String name;
  final String receiverPhone;
  final String distance;
  final String position;

  const ChatPage({
    super.key,
    required this.name,
    required this.receiverPhone,
    required this.distance,
    required this.position,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isBlocked = false;
  String? _blockerPhone;
  late IO.Socket socket;
  Map<String, dynamic>? currentUser;
  bool _isOtherTyping = false;
  bool _isOnline = false;
  Timer? _typingTimer;

  String? _editingMessageId;
  ChatMessage? _replyingToMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSocket();
    _loadUserAndHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // This is called when the keyboard opens/closes
    _scrollToBottom();
  }

  Future<void> _loadUserAndHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      setState(() {
        currentUser = jsonDecode(userData);
      });
      _joinRoom();
    }
    _checkBlockStatus();
    _fetchChatHistory();
    _markMessagesAsSeen();
    _fetchReceiverStatus();
  }

  void _joinRoom() {
    if (currentUser != null) {
      socket.emit('set_online', currentUser!['phone']); // Tell server I'm online
      socket.emit('join_room', _getRoomId());
    }
  }

  Future<void> _fetchReceiverStatus() async {
    try {
      final response = await ApiService.get('/api/admin/user/${widget.receiverPhone}/full');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => _isOnline = data['user']['isOnline'] ?? false);
      }
    } catch (e) {}
  }

  Future<void> _checkBlockStatus() async {
    if (currentUser == null) return;
    try {
      final res1 = await ApiService.get('/api/chat/check-block/${currentUser!['phone']}/${widget.receiverPhone}');
      final res2 = await ApiService.get('/api/chat/check-block/${widget.receiverPhone}/${currentUser!['phone']}');
      if (mounted) {
        bool iBlocked = jsonDecode(res1.body)['isBlocked'] ?? false;
        bool theyBlocked = jsonDecode(res2.body)['isBlocked'] ?? false;
        setState(() {
          _isBlocked = iBlocked || theyBlocked;
          _blockerPhone = iBlocked ? currentUser!['phone'] : (theyBlocked ? widget.receiverPhone : null);
        });
      }
    } catch (e) {}
  }

  Future<void> _fetchChatHistory() async {
    if (currentUser == null) return;
    try {
      final response = await http.get(Uri.parse('http://72.61.170.181:5000/api/admin/chat-history/${currentUser!['phone']}/${widget.receiverPhone}'));
      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _messages.clear();
            for (var msg in history) {
              _messages.add(ChatMessage(
                id: msg['_id'],
                text: msg['message'],
                imageUrl: msg['imageUrl'],
                audioUrl: msg['audioUrl'],
                type: msg['type'] ?? 'text',
                isViewOnce: msg['isViewOnce'] ?? false,
                isOpened: msg['isOpened'] ?? false,
                isMe: msg['senderPhone'] == currentUser!['phone'],
                timestamp: DateTime.parse(msg['timestamp'] ?? DateTime.now().toIso8601String()).toLocal(),
                isDelivered: msg['isDelivered'] ?? true, // Default to true for history
                isSeen: msg['isOpened'] ?? false,
              ));
            }
          });
          _scrollToBottom();
        }
      }
    } catch (e) {}
  }

  String _getRoomId() {
    List<String> ids = [currentUser?['phone'] ?? 'Me', widget.receiverPhone];
    ids.sort();
    return ids.join('_');
  }

  void _initSocket() {
    socket = IO.io('http://72.61.170.181:5000', <String, dynamic>{'transports': ['websocket'], 'autoConnect': true});
    socket.onConnect((_) { 
      if (currentUser != null) {
        socket.emit('set_online', currentUser!['phone']);
      }
      _joinRoom(); 
    });
    socket.on('receive_message', (data) {
      if (mounted) {
        setState(() {
          if (data['senderPhone'] == currentUser?['phone']) {
            _messages.removeWhere((m) => m.id != null && m.id!.startsWith('temp_') && m.text == data['message']);
          }
          if (_messages.any((m) => m.id == data['_id'])) return;
          
          bool isMe = data['senderPhone'] == currentUser?['phone'];
          
          _messages.add(ChatMessage(
            id: data['_id'],
            text: data['message'],
            imageUrl: data['imageUrl'],
            audioUrl: data['audioUrl'],
            type: data['type'] ?? 'text',
            isViewOnce: data['isViewOnce'] ?? false,
            isOpened: data['isOpened'] ?? false,
            isMe: isMe,
            timestamp: DateTime.parse(data['timestamp'] ?? DateTime.now().toIso8601String()).toLocal(),
            isDelivered: data['isDelivered'] ?? true,
            isSeen: data['isOpened'] ?? false,
          ));

          // If I am the receiver and I'm currently in this chat, mark it as seen immediately
          if (!isMe) {
            socket.emit('mark_opened', {
              'messageId': data['_id'], 
              'myPhone': currentUser!['phone'], 
              'otherPhone': widget.receiverPhone
            });
          }
        });
        _scrollToBottom();
      }
    });
    socket.on('message_delivered', (data) {
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == data['messageId']);
          if (index != -1) _messages[index].isDelivered = true;
        });
      }
    });
    socket.on('message_opened', (data) {
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == data['messageId']);
          if (index != -1) {
            _messages[index].isOpened = true;
            _messages[index].isSeen = true;
          }
        });
      }
    });
    socket.on('chat_seen_update', (data) {
      if (mounted) {
        setState(() {
          for (var msg in _messages) {
            if (msg.isMe) {
              msg.isSeen = true;
              msg.isDelivered = true;
            }
          }
        });
      }
    });
    socket.on('message_deleted', (data) { if (mounted) setState(() => _messages.removeWhere((m) => m.id == data['messageId'])); });
    socket.on('message_edited', (data) { if (mounted) { setState(() { final index = _messages.indexWhere((m) => m.id == data['messageId']); if (index != -1) { _messages[index].text = data['newText']; _messages[index].isEdited = true; } }); } });
    socket.on('chat_status_update', (data) { if (mounted) { _checkBlockStatus(); _fetchChatHistory(); } });
    socket.on('display_typing', (data) { 
      if (mounted && data['phone'] == widget.receiverPhone) {
        setState(() => _isOtherTyping = true);
        _scrollToBottom();
      }
    });
    socket.on('hide_typing', (data) { if (mounted && data['phone'] == widget.receiverPhone) setState(() => _isOtherTyping = false); });
    socket.on('user_status_change', (data) { if (mounted && data['phone'] == widget.receiverPhone) setState(() => _isOnline = data['isOnline'] ?? false); });
  }

  Future<void> _markMessagesAsSeen() async {
    if (currentUser == null) return;
    // Mark all messages from this specific user as seen
    socket.emit('mark_chat_seen', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
  }

  Future<void> _uploadAudio(String path) async {
    setState(() => _isLoading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('http://72.61.170.181:5000/api/chat/upload'));
      request.files.add(await http.MultipartFile.fromPath('image', path));
      var response = await request.send();
      if (response.statusCode == 200) {
        var resBody = await http.Response.fromStream(response);
        var data = jsonDecode(resBody.body);
        socket.emit('send_message', {'senderPhone': currentUser!['phone'], 'receiverPhone': widget.receiverPhone, 'message': '', 'audioUrl': data['imageUrl'], 'type': 'audio'});
      }
    } catch (e) {}
    setState(() => _isLoading = false);
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || currentUser == null) return;
    String msgText = _messageController.text.trim();
    if (_editingMessageId != null) {
      if (_isBlocked) return;
      socket.emit('edit_message', {'messageId': _editingMessageId, 'newText': msgText, 'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
      setState(() { _editingMessageId = null; _messageController.clear(); });
    } else {
      final tempMsg = ChatMessage(id: 'temp_${DateTime.now().millisecondsSinceEpoch}', text: msgText, isMe: true, type: 'text', timestamp: DateTime.now());
      setState(() => _messages.add(tempMsg));
      if (!_isBlocked) socket.emit('send_message', {'senderPhone': currentUser!['phone'], 'receiverPhone': widget.receiverPhone, 'message': msgText, 'type': 'text'});
      setState(() { _messageController.clear(); _replyingToMessage = null; });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() { Future.delayed(const Duration(milliseconds: 100), () { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); }); }

  void _showContextMenu(ChatMessage msg) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(
      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12), Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ['😆', '😂', '😡', '😮', '😥', '➕'].map((e) => GestureDetector(onTap: () => Navigator.pop(context), child: Text(e, style: const TextStyle(fontSize: 28)))).toList())),
        const Divider(color: Colors.white10),
        ListTile(leading: const Icon(Icons.reply_rounded, color: Colors.orangeAccent), title: const Text('Reply', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() => _replyingToMessage = msg); }),
        ListTile(leading: const Icon(Icons.copy_all_rounded, color: Colors.orangeAccent), title: const Text('Copy Message', style: TextStyle(color: Colors.white)), onTap: () { Clipboard.setData(ClipboardData(text: msg.text ?? '')); Navigator.pop(context); }),
        if (msg.isMe && msg.type == 'text') ListTile(leading: const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent), title: const Text('Edit', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() { _editingMessageId = msg.id; _messageController.text = msg.text ?? ''; }); }),
        if (msg.isMe) ListTile(leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent), title: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.pop(context); _confirmDelete(msg); }),
        const SizedBox(height: 15),
      ])),
    ));
  }

  void _confirmDelete(ChatMessage msg) {
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF1A1A1A), title: const Text('Delete?'), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
      ElevatedButton(onPressed: () { socket.emit('delete_message', {'messageId': msg.id, 'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone}); Navigator.pop(context); }, child: const Text('DELETE')),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17), elevation: 1, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0, title: GestureDetector(onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileDetailPage(name: widget.name, phone: widget.receiverPhone, distance: widget.distance, city: 'Unknown', area: 'Unknown', age: 18, position: widget.position, havePlace: 'Unknown', showMessageButton: false))); },
          child: Row(children: [
            const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white54)), const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.name.split(' ').first}, ${widget.position}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              Row(children: [Text(widget.distance, style: const TextStyle(fontSize: 12, color: Colors.white54)), if (_isOnline) ...[const SizedBox(width: 4), const Text('●Online', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))]])
            ])
          ]),
        ),
        actions: [IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent), onPressed: () async { final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => ChatSettingsPage(name: widget.name, phone: widget.receiverPhone, socket: socket))); if (result == true) _loadUserAndHistory(); })],
      ),
      body: Column(children: [Expanded(child: _buildMessageList()), if (_isLoading) const LinearProgressIndicator(color: Colors.orangeAccent), _buildInputArea()]),
    );
  }

  Widget _buildMessageList() {
    List<Widget> children = [];
    
    // If no messages, show safety banner at top
    if (_messages.isEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(_buildSafetyBanner());
    }

    if (_messages.isNotEmpty) {
      DateTime? lastDate;
      for (int i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (lastDate == null || DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day) != lastDate) {
          children.add(Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 20), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Text(DateFormat('EEE, MMM d').format(msg.timestamp), style: const TextStyle(color: Colors.white60, fontSize: 11)))));
          lastDate = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
          
          // Show safety banner after first date header
          if (i == 0) {
            children.add(_buildSafetyBanner());
          }
        }
        children.add(Padding(padding: const EdgeInsets.only(bottom: 15, left: 20, right: 20), child: GestureDetector(onLongPress: () => _showContextMenu(msg), child: _buildMessageItem(msg))));
      }
    }
    
    if (_isOtherTyping) children.add(_buildTypingIndicator());
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      children: children,
    );
  }

  Widget _buildSafetyBanner() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4).withOpacity(0.9), // Light Yellow
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_box_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  'अपनी कम्युनिटी को सेफ रखें',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'अगर कोई यूजर पैसे मांगta है, तो तुरंत रिपोर्ट करें - हम तुरंत एक्शन लेंगे।',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withOpacity(0.7),
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(padding: const EdgeInsets.only(left: 20, bottom: 15), child: Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.name.split(' ').first, style: const TextStyle(color: Colors.white54, fontSize: 10)), const SizedBox(height: 4),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: const BoxDecoration(color: Color(0xFF2A2A2A), borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(16))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 3, backgroundColor: Colors.white38), SizedBox(width: 4), CircleAvatar(radius: 3, backgroundColor: Colors.white38), SizedBox(width: 4), CircleAvatar(radius: 3, backgroundColor: Colors.white38)]),
      )
    ])));
  }

  Widget _buildMessageItem(ChatMessage msg) {
    if (msg.type == 'block_event') return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(25)), child: Text(msg.isMe ? 'You blocked ${widget.name}' : '${widget.name} blocked you', style: const TextStyle(color: Colors.white, fontSize: 12))));
    if (msg.type == 'unblock_event') return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.8), borderRadius: BorderRadius.circular(25)), child: const Text('Unblocked', style: TextStyle(color: Colors.white, fontSize: 12))));
    return Align(alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft, child: _buildChatBubble(msg));
  }

  Widget _buildInputArea() {
    bool isBlockedByMe = _isBlocked && _blockerPhone == currentUser?['phone'];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_isBlocked) Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20), color: Colors.red.withOpacity(0.1), child: Center(child: Text(isBlockedByMe ? 'You blocked this user.' : 'This chat is currently blocked', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)))),
      if (_replyingToMessage != null) Container(padding: const EdgeInsets.all(12), color: Colors.white.withOpacity(0.05), child: Row(children: [Container(width: 4, height: 40, color: Colors.orangeAccent), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_replyingToMessage!.isMe ? 'You' : widget.name, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)), Text(_replyingToMessage!.text ?? 'Image', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1)]))])),
      Container(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
        color: const Color(0xFF1A1A1A),
        child: Row(children: [
        GestureDetector(onTap: () { if (_isBlocked) return; _showMediaPopup(); }, child: const Icon(Icons.add_box_rounded, color: Colors.orangeAccent, size: 28)), const SizedBox(width: 12),
        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), height: 45, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25)), child: TextField(
          controller: _messageController, 
          onSubmitted: (val) => _sendMessage(),
          onTap: () => _scrollToBottom(), // Scroll when clicking on text field
          onChanged: (val) { 
            if (_isBlocked) return; 
            socket.emit('typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone}); 
            _typingTimer?.cancel(); 
            _typingTimer = Timer(const Duration(seconds: 2), () => socket.emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone})); 
            setState(() {}); 
          }, 
          decoration: const InputDecoration(hintText: 'Enter message', border: InputBorder.none)))),
        const SizedBox(width: 12),
        _messageController.text.trim().isEmpty ? GestureDetector(onTap: () { if (_isBlocked) return; _showVoiceRecorderModal(); }, child: const Icon(Icons.mic_rounded, color: Colors.orangeAccent, size: 28)) : GestureDetector(onTap: _sendMessage, child: const Icon(Icons.send_rounded, color: Colors.orangeAccent, size: 28))
      ]))
    ]);
  }

  void _showMediaPopup() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => MediaSelectionModal(currentUserPhone: currentUser!['phone'], onMediaSelected: (file, type, {String? url}) => _handleImagePreview(file, type, url: url)));
  }

  Future<void> _handleImagePreview(File file, String type, {String? url}) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => MediaPreviewPage(file: file, imageUrl: url)));
    if (result != null && result is Map<String, dynamic>) {
      setState(() => _isLoading = true);
      String? finalUrl = url;
      if (finalUrl == null && file.path.isNotEmpty) {
        var request = http.MultipartRequest('POST', Uri.parse('http://72.61.170.181:5000/api/chat/upload'));
        request.files.add(await http.MultipartFile.fromPath('image', file.path));
        // Include phone to save in RecentPhoto model
        request.fields['phone'] = currentUser!['phone'];
        var response = await request.send();
        if (response.statusCode == 200) {
          var resBody = await http.Response.fromStream(response);
          finalUrl = jsonDecode(resBody.body)['imageUrl'];
          // Note: Since _fetchRecentPhotos is now inside MediaSelectionModal, 
          // we don't need to call it here as the modal is closed after selection.
        }
      }
      if (finalUrl != null) {
        socket.emit('send_message', {'senderPhone': currentUser!['phone'], 'receiverPhone': widget.receiverPhone, 'message': '', 'imageUrl': finalUrl, 'type': type == 'video' ? 'video' : 'image', 'isViewOnce': result['isViewOnce']});
      }
      setState(() => _isLoading = false);
    }
  }

  void _showVoiceRecorderModal() { showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isDismissible: false, builder: (context) => VoiceRecorderModal(onSend: (path) => _uploadAudio(path))); }

  Widget _buildAudioBubble(ChatMessage msg) { return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)), child: AudioPlayerWidget(url: msg.audioUrl!, isMe: msg.isMe)); }

  Widget _buildChatBubble(ChatMessage msg) {
    return Column(crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (msg.type == 'audio') _buildAudioBubble(msg)
      else if (msg.imageUrl != null)
        GestureDetector(
          onTap: () async {
            bool canView = !msg.isViewOnce || (msg.isViewOnce && !msg.isMe && !msg.isOpened);
            if (canView) {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => FullScreenImageViewer(imageUrl: msg.imageUrl!)));
              if (msg.isViewOnce && !msg.isOpened) {
                socket.emit('mark_opened', {'messageId': msg.id, 'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
                setState(() {
                  msg.isOpened = true;
                  msg.isSeen = true;
                });
              }
            }
          },
          child: Container(
            padding: msg.isViewOnce ? const EdgeInsets.all(12) : EdgeInsets.zero,
            decoration: BoxDecoration(color: msg.isViewOnce ? (msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A)) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
            child: msg.isViewOnce
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(msg.isOpened ? Icons.done_all : Icons.looks_one, color: msg.isMe ? Colors.black : (msg.isOpened ? Colors.greenAccent : Colors.orangeAccent), size: 20),
                    const SizedBox(width: 8),
                    Text(msg.isOpened ? 'Opened' : 'Photo', style: TextStyle(color: msg.isMe ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                    if (!msg.isMe && !msg.isOpened) ...[
                      const SizedBox(width: 12),
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: CachedNetworkImage(imageUrl: msg.imageUrl!, width: 40, height: 40, fit: BoxFit.cover)))
                    ]
                  ])
                : ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: msg.imageUrl!, width: 200, height: 200, fit: BoxFit.cover)),
          ),
        )
      else Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(16)), child: Text(msg.text ?? '', style: TextStyle(color: msg.isMe ? Colors.black : Colors.white))),
      Padding(padding: const EdgeInsets.only(top: 4), child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('h:mm a').format(msg.timestamp), style: const TextStyle(color: Colors.white54, fontSize: 10)),
          if (msg.isMe) ...[
            const SizedBox(width: 4),
            _buildTicks(msg),
          ]
        ],
      ))
    ]);
  }

  Widget _buildTicks(ChatMessage msg) {
    if (msg.isSeen || msg.isOpened) {
      return const Icon(Icons.done_all, color: Colors.greenAccent, size: 15);
    } else if (msg.isDelivered) {
      return const Icon(Icons.done_all, color: Colors.grey, size: 15);
    } else {
      return const Icon(Icons.done, color: Colors.grey, size: 15);
    }
  }
}

class MediaSelectionModal extends StatefulWidget {
  final String currentUserPhone;
  final Function(File, String, {String? url}) onMediaSelected;
  const MediaSelectionModal({super.key, required this.currentUserPhone, required this.onMediaSelected});
  @override
  State<MediaSelectionModal> createState() => _MediaSelectionModalState();
}
class _MediaSelectionModalState extends State<MediaSelectionModal> {
  List<dynamic> _recentPhotos = [];
  bool _isEditMode = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchRecentPhotos();
  }

  Future<void> _fetchRecentPhotos() async {
    try {
      // Adding a timestamp to prevent cached results from the server
      final url = 'http://72.61.170.181:5000/api/chat/recent-photos/${widget.currentUserPhone}?t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final List<dynamic> fetchedPhotos = jsonDecode(res.body)['photos'];
        if (mounted) {
          setState(() {
            _recentPhotos = fetchedPhotos;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _deletePhoto(String id) async {
    // 1. Permanently remove from the local list FIRST
    setState(() {
      _recentPhotos.removeWhere((p) => p['_id'] == id);
    });

    try {
      // Call delete API silently
      await http.delete(Uri.parse('http://72.61.170.181:5000/api/chat/photo/$id'));
    } catch (e) {
      print("Delete error: $e");
    }
    
    // No more refreshing! The image stays gone from the UI.
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Elegant Handle Bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 25),
          // Action Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionItem(Icons.camera_alt_rounded, 'Camera', Colors.blueAccent, () async {
                final f = await _picker.pickImage(source: ImageSource.camera);
                if (f != null) { Navigator.pop(context); widget.onMediaSelected(File(f.path), 'image'); }
              }),
              _buildActionItem(Icons.videocam_rounded, 'Video', Colors.redAccent, () async {
                final f = await _picker.pickVideo(source: ImageSource.camera);
                if (f != null) { Navigator.pop(context); widget.onMediaSelected(File(f.path), 'video'); }
              }),
              _buildActionItem(Icons.image_rounded, 'Gallery', Colors.greenAccent, () async {
                final f = await _picker.pickImage(source: ImageSource.gallery);
                if (f != null) { Navigator.pop(context); widget.onMediaSelected(File(f.path), 'image'); }
              }),
              _buildActionItem(Icons.audio_file_rounded, 'Audio', Colors.orangeAccent, () {
                Navigator.pop(context);
                // Trigger voice recorder directly or similar action
              }),
            ],
          ),
          const SizedBox(height: 35),
          // Recent Photos Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Recent Photos', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton(
                onPressed: () => setState(() => _isEditMode = !_isEditMode),
                style: TextButton.styleFrom(
                  backgroundColor: _isEditMode ? Colors.orangeAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  _isEditMode ? 'Done' : 'Edit',
                  style: TextStyle(
                    color: _isEditMode ? Colors.orangeAccent : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Recent Photos List
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildAddRecentItem(),
                ..._recentPhotos.map((p) => _buildRecentImageItem(p)),
              ],
            ),
          ),
          // Adding safe area padding at the bottom to avoid system navigation bar overlap
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildAddRecentItem() {
    return GestureDetector(
      onTap: () async {
        final f = await _picker.pickImage(source: ImageSource.gallery);
        if (f != null) { Navigator.pop(context); widget.onMediaSelected(File(f.path), 'image'); }
      },
      child: Container(
        width: 90,
        height: 110,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.orangeAccent, size: 32),
      ),
    );
  }

  Widget _buildRecentImageItem(dynamic p) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            if (!_isEditMode) {
              Navigator.pop(context);
              widget.onMediaSelected(File(''), 'image', url: p['imageUrl']);
            }
          },
          child: Container(
            width: 90,
            height: 110,
            margin: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: CachedNetworkImage(
                imageUrl: p['imageUrl'],
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.white10),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
          ),
        ),
        if (_isEditMode)
          Positioned(
            top: 5,
            right: 17,
            child: GestureDetector(
              onTap: () => _deletePhoto(p['_id']),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                child: const Icon(Icons.delete_forever_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class VoiceRecorderModal extends StatefulWidget {
  final Function(String) onSend;
  const VoiceRecorderModal({super.key, required this.onSend});
  @override
  State<VoiceRecorderModal> createState() => _VoiceRecorderModalState();
}
class _VoiceRecorderModalState extends State<VoiceRecorderModal> {
  final AudioRecorder _recorder = AudioRecorder(); bool _isRecording = false; String? _path; int _seconds = 0; Timer? _timer;
  void _startTimer() { _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _seconds++)); }
  void _stopTimer() { _timer?.cancel(); }
  @override
  void dispose() { _recorder.dispose(); _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white, fontSize: 18)), const SizedBox(height: 20),
      GestureDetector(onTap: () async {
        if (_isRecording) { final p = await _recorder.stop(); _stopTimer(); setState(() { _isRecording = false; _path = p; }); }
        else { if (await Permission.microphone.request().isGranted) { final dir = await getApplicationDocumentsDirectory(); final p = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a'; await _recorder.start(const RecordConfig(), path: p); _startTimer(); setState(() { _isRecording = true; _seconds = 0; }); } }
      }, child: CircleAvatar(radius: 35, backgroundColor: _isRecording ? Colors.red : Colors.orangeAccent, child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.black))),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))), ElevatedButton(onPressed: _path == null ? null : () { widget.onSend(_path!); Navigator.pop(context); }, child: const Text('Send'))])
    ])));
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final String url; final bool isMe;
  const AudioPlayerWidget({super.key, required this.url, required this.isMe});
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}
class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer(); bool _isPlaying = false; Duration _duration = Duration.zero; Duration _position = Duration.zero;
  @override
  void initState() { super.initState(); _player.onDurationChanged.listen((d) => setState(() => _duration = d)); _player.onPositionChanged.listen((p) => setState(() => _position = p)); _player.onPlayerComplete.listen((_) => setState(() => _isPlaying = false)); }
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: widget.isMe ? Colors.black : Colors.orangeAccent), onPressed: () async { if (_isPlaying) { await _player.pause(); setState(() => _isPlaying = false); } else { await _player.play(UrlSource(widget.url)); setState(() => _isPlaying = true); } }),
      Text('${_position.inSeconds}/${_duration.inSeconds}', style: TextStyle(color: widget.isMe ? Colors.black : Colors.white70, fontSize: 10))
    ]);
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const FullScreenImageViewer({super.key, required this.imageUrl});
  @override
  Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, body: Center(child: InteractiveViewer(child: Image.network(imageUrl)))); }
}

class MediaPreviewPage extends StatelessWidget {
  final File file; final String? imageUrl;
  const MediaPreviewPage({super.key, required this.file, this.imageUrl});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Column(children: [
          Expanded(child: Center(child: imageUrl != null ? Image.network(imageUrl!) : Image.file(file))),
          Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              ElevatedButton(onPressed: () => Navigator.pop(context, {'isViewOnce': true}), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFA000), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('View once ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), Icon(Icons.looks_one, color: Colors.black, size: 18)])),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => Navigator.pop(context, {'isViewOnce': false}), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))), child: const Text('View many time', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
            ])),
        ])),
    );
  }
}
