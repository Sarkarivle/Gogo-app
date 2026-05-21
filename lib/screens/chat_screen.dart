import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../services/socket_service.dart';
import '../services/chat_repository.dart';
import '../services/premium_service.dart';
import 'chat_settings_screen.dart';
import 'profile_detail_screen.dart';
import 'onboarding/payment_screen.dart';

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
  final List<ChatMessage> _messages = [];
  
  bool _isLoadingHistory = false;
  bool _isLoadingMore = false;
  int _currentHistoryPage = 1;
  bool _hasMoreHistory = true;
  bool _isBlocked = false;
  String? _blockerPhone;
  Map<String, dynamic>? currentUser;
  Timer? _typingTimer;
  
  StreamSubscription? _socketMsgSub;
  StreamSubscription? _socketEventSub;

  String? _editingMessageId;
  ChatMessage? _replyingToMessage;

  final ChatRepository _chatRepository = ChatRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_onTextChanged);
    _loadUserAndHistory();
    _listenToSocket();
    
    _scrollController.addListener(_onScroll);
    SocketService().typingUsers.addListener(_handleTypingScroll);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100 && !_isLoadingMore && _hasMoreHistory && !_isLoadingHistory) {
      _fetchChatHistory(loadMore: true);
    }
  }

  void _handleTypingScroll() {
    final bool isTyping = SocketService().typingUsers.value[widget.receiverPhone] ?? false;
    if (isTyping && _scrollController.hasClients && _scrollController.position.pixels > _scrollController.position.maxScrollExtent - 100) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    SocketService().typingUsers.removeListener(_handleTypingScroll);
    SocketService().leaveRoom();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _socketMsgSub?.cancel();
    _socketEventSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scrollToBottom(immediate: true);
  }

  // --- LOGIC ---

  Future<void> _loadUserAndHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      currentUser = jsonDecode(userData);
      final roomId = _getRoomId();
      SocketService().joinRoom(roomId);
      _chatRepository.markChatSeen(currentUser!['phone'], widget.receiverPhone);
    }
    _checkBlockStatus();
    _fetchChatHistory();
  }

  void _listenToSocket() {
    _socketMsgSub = SocketService().messageStream.listen((data) {
      if (data['roomId'] == _getRoomId()) {
        _handleIncomingMessage(data);
      }
    });

    _socketEventSub = SocketService().eventStream.listen((event) {
      final data = event['data'];
      if (!mounted) return;

      setState(() {
        switch (event['event']) {
          case 'moderation_state_updated':
            if (data['roomId'] == _getRoomId()) {
              _isBlocked = data['isBlocked'] ?? false;
              _blockerPhone = data['blockerPhone'];
              if (_isBlocked) {
                SocketService().emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
              }
            }
            break;
          case 'message_delivered':
            final idx = _messages.indexWhere((m) => m.id == data['messageId']);
            if (idx != -1) _messages[idx].status = MessageStatus.delivered;
            break;
          case 'message_opened':
            final idx = _messages.indexWhere((m) => m.id == data['messageId']);
            if (idx != -1) {
              _messages[idx].status = MessageStatus.seen;
              _messages[idx].isOpened = true;
              if (_messages[idx].isViewOnce) {
                _messages[idx].imageUrl = null;
              }
            }
            break;
          case 'chat_seen_update':
            for (var m in _messages) if (m.isMe) m.status = MessageStatus.seen;
            break;
          case 'message_deleted_for_everyone':
            final idx = _messages.indexWhere((m) => m.id == data['messageId']);
            if (idx != -1) {
              _messages[idx].isDeletedForEveryone = true;
              _messages[idx].imageUrl = null;
              _messages[idx].audioUrl = null;
            }
            break;
          case 'message_deleted':
            _messages.removeWhere((m) => m.id == data['messageId']);
            break;
          case 'message_edited':
            final idx = _messages.indexWhere((m) => m.id == data['messageId']);
            if (idx != -1) {
              _messages[idx].text = data['newText'];
              _messages[idx].isEdited = true;
            }
            break;
          case 'chat_status_update':
            _checkBlockStatus();
            break;
        }
      });
    });
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;
    
    final newMessage = ChatMessage.fromJson(data, currentUser?['phone'] ?? '');
    
    setState(() {
      if (newMessage.isMe) {
        _messages.removeWhere((m) => 
          (m.localId != null && m.localId == data['localId']) || 
          (m.status == MessageStatus.sending && m.text == newMessage.text)
        );
      }
      
      if (!_messages.any((m) => m.id == newMessage.id)) {
        _messages.add(newMessage);
        if (!newMessage.isMe) {
          SocketService().setTyping(widget.receiverPhone, false);
          if (!newMessage.isViewOnce) {
            _chatRepository.markOpened(newMessage.id!, currentUser!['phone'], widget.receiverPhone);
          }
        }
      }
    });
    _scrollToBottom();
  }

  Future<void> _fetchChatHistory({bool loadMore = false}) async {
    if (currentUser == null || (loadMore && !_hasMoreHistory)) return;
    
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() => _isLoadingHistory = true);
    }

    try {
      final page = loadMore ? _currentHistoryPage + 1 : 1;
      final newMsgs = await _chatRepository.getChatHistory(
        myPhone: currentUser!['phone'],
        otherPhone: widget.receiverPhone,
        page: page,
        limit: 30
      );
      
      if (mounted) {
        setState(() {
          if (loadMore) {
            _messages.insertAll(0, newMsgs);
            _currentHistoryPage++;
          } else {
            _messages.clear();
            _messages.addAll(newMsgs);
            _currentHistoryPage = 1;
          }
          _hasMoreHistory = newMsgs.length >= 30;
        });

        if (!loadMore) {
          _scrollToBottom(immediate: true);
        }
      }
    } catch (e) {
      debugPrint("History error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    if (currentUser == null) return;
    final isBlocked = await _chatRepository.checkBlockStatus(currentUser!['phone'], widget.receiverPhone);
    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  String _getRoomId() {
    List<String> ids = [currentUser?['phone'] ?? 'Me', widget.receiverPhone];
    ids.sort();
    return ids.join('_');
  }

  // --- ACTIONS ---

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || currentUser == null) return;

    final isPremium = await PremiumService().checkPremiumAndRedirect(context);
    if (!isPremium) return;

    if (_editingMessageId != null) {
      _chatRepository.editMessage(_editingMessageId!, text, currentUser!['phone'], widget.receiverPhone);
      setState(() => _editingMessageId = null);
      _messageController.clear();
      return;
    }

    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMsg = ChatMessage(
      localId: localId,
      text: text,
      isMe: true,
      timestamp: DateTime.now(),
      status: _isBlocked ? MessageStatus.error : MessageStatus.sending,
      replyToId: _replyingToMessage?.id,
      replyText: _replyingToMessage?.text,
      replyType: _replyingToMessage?.type,
    );

    setState(() {
      _messages.add(optimisticMsg);
      _replyingToMessage = null;
      _messageController.clear();
    });
    _scrollToBottom();

    if (_isBlocked) return;

    _chatRepository.sendMessage(
      senderPhone: currentUser!['phone'],
      receiverPhone: widget.receiverPhone,
      senderName: currentUser!['name'] ?? 'User',
      message: text,
      localId: localId,
      replyToId: optimisticMsg.replyToId,
      replyText: optimisticMsg.replyText,
      replyType: optimisticMsg.replyType,
      ack: (ack) {
        if (mounted && ack != null) {
          if (ack['success'] == false) {
            setState(() => optimisticMsg.status = MessageStatus.error);
          }
        }
      }
    );
  }

  Future<void> _uploadMedia(File file, String type, {bool isViewOnce = false}) async {
    if (currentUser == null) return;
    
    final isPremium = await PremiumService().checkPremiumAndRedirect(context);
    if (!isPremium) return;

    if (_isBlocked) {
      final localId = DateTime.now().millisecondsSinceEpoch.toString();
      setState(() {
        _messages.add(ChatMessage(
          localId: localId,
          text: type == 'image' ? '📷 Image' : '🎵 Voice Message',
          isMe: true,
          timestamp: DateTime.now(),
          status: MessageStatus.error,
          type: type,
        ));
      });
      _scrollToBottom();
      return;
    }

    setState(() => _isLoadingHistory = true);
    try {
      final url = await _chatRepository.uploadMedia(file, currentUser!['phone'], type);
      if (url != null) {
        _chatRepository.sendMessage(
          senderPhone: currentUser!['phone'],
          receiverPhone: widget.receiverPhone,
          senderName: currentUser!['name'] ?? 'User',
          message: '',
          imageUrl: type != 'audio' ? url : null,
          audioUrl: type == 'audio' ? url : null,
          type: type,
          isViewOnce: isViewOnce
        );
      }
    } catch (e) {
      debugPrint("Upload error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final double target = _scrollController.position.maxScrollExtent;
        if (immediate) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _buildHeader(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_isLoadingHistory) const LinearProgressIndicator(color: Colors.orangeAccent, minHeight: 1),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: const Color(0xFF2A0D17),
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailPage(
          name: widget.name, phone: widget.receiverPhone, distance: widget.distance, city: 'Unknown', area: 'Unknown', age: 18, position: widget.position, havePlace: 'Unknown', showMessageButton: false
        ))),
        child: Row(
          children: [
            const CircleAvatar(radius: 18, backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white54, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ValueListenableBuilder<Map<String, bool>>(
                    valueListenable: SocketService().onlineUsers,
                    builder: (context, onlineMap, _) {
                      final bool isOnline = onlineMap[widget.receiverPhone] ?? false;
                      return Row(
                        children: [
                          Text(widget.distance, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                          if (isOnline) ...[
                            const SizedBox(width: 6),
                            const Text('● Online', style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.w800)),
                          ]
                        ],
                      );
                    }
                  )
                ],
              ),
            )
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent),
          onPressed: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSettingsPage(name: widget.name, phone: widget.receiverPhone)));
            if (result == true) _loadUserAndHistory();
          }
        )
      ],
    );
  }

  Widget _buildMessageList() {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: SocketService().typingUsers,
      builder: (context, typingMap, _) {
        final bool isTyping = typingMap[widget.receiverPhone] ?? false;
        
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: _messages.length + (isTyping ? 1 : 0) + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (_isLoadingMore && index == 0) {
              return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)));
            }
            
            final adjustedIndex = _isLoadingMore ? index - 1 : index;

            if (adjustedIndex == _messages.length) {
              return _buildTypingIndicator();
            }

            final msg = _messages[adjustedIndex];
            final showDateHeader = adjustedIndex == 0 || !_isSameDay(_messages[adjustedIndex - 1].timestamp, msg.timestamp);

            return Column(
              children: [
                if (showDateHeader) _buildDateHeader(msg.timestamp),
                _buildMessageBubble(msg),
              ],
            );
          },
        );
      }
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Text(
        _getFormattedDate(date),
        style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    if (msg.isDeletedForEveryone) return const SizedBox.shrink();

    if (msg.type == 'block_event' || msg.type == 'unblock_event') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(color: msg.type == 'block_event' ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(
            msg.type == 'block_event' ? (msg.isMe ? 'You blocked ${widget.name}' : 'You were blocked') : 'Chat Unblocked',
            style: TextStyle(color: msg.type == 'block_event' ? Colors.redAccent : Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: () => _showContextMenu(msg),
        child: Align(
          alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (msg.replyToId != null) _buildReplyPreview(msg),
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                padding: EdgeInsets.symmetric(
                  horizontal: msg.isViewOnce ? 12 : 14, 
                  vertical: msg.isViewOnce ? 8 : 10
                ),
                decoration: BoxDecoration(
                  color: msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(msg.isMe ? 18 : 0),
                    bottomRight: Radius.circular(msg.isMe ? 0 : 18),
                  ),
                ),
                child: _buildBubbleContent(msg),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('h:mm a').format(msg.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  if (msg.isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(msg.status),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleContent(ChatMessage msg) {
    if (msg.type == 'image' || msg.imageUrl != null) {
      if (msg.isViewOnce) {
        return _buildViewOnceImage(msg);
      }
      return _buildImageContent(msg);
    } else if (msg.type == 'audio') {
      return AudioPlayerWidget(url: msg.audioUrl!, isMe: msg.isMe);
    }
    return Text(msg.text ?? '', style: TextStyle(color: msg.isMe ? Colors.black : Colors.white, fontSize: 15, height: 1.3));
  }

  Widget _buildImageContent(ChatMessage msg) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: msg.imageUrl!))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: msg.imageUrl!,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: Colors.white10, width: 200, height: 200),
          errorWidget: (_, __, ___) => const Icon(Icons.error, color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildViewOnceImage(ChatMessage msg) {
    bool isOpened = msg.isOpened;

    // Sender View (Always a small bubble)
    if (msg.isMe) {
      if (!isOpened) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.looks_one_rounded, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Photo', 
              style: TextStyle(
                color: Colors.black, 
                fontWeight: FontWeight.bold, 
                fontSize: 13,
                letterSpacing: 0.5
              )
            ),
          ],
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.done_all, color: Colors.black54, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Opened', 
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.bold, 
                fontSize: 14,
                letterSpacing: 0.5
              )
            ),
          ],
        );
      }
    }

    // Receiver View
    if (isOpened) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drafts_outlined, color: Colors.white12, size: 20),
          const SizedBox(width: 10),
          const Text(
            'Opened', 
            style: TextStyle(
              color: Colors.white12, 
              fontWeight: FontWeight.bold, 
              fontSize: 14,
            )
          ),
        ],
      );
    }

    // Unopened Receiver Side (Blurred Box)
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(
          imageUrl: msg.imageUrl!,
          isViewOnce: true,
        )));
        
        _chatRepository.markOpened(msg.id!, currentUser!['phone'], widget.receiverPhone);
        
        setState(() {
          msg.isOpened = true;
          msg.imageUrl = null;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 150,
          height: 150,
          color: const Color(0xFF1E1E1E),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (msg.imageUrl != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: CachedNetworkImage(
                    imageUrl: msg.imageUrl!,
                    width: 150,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
              Container(color: Colors.black.withOpacity(0.3)),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.looks_one_rounded, color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Photo', 
                    style: TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 13,
                      letterSpacing: 0.5
                    )
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, height: 20, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Flexible(child: Text(msg.replyText ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending: return const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orangeAccent));
      case MessageStatus.sent: return const Icon(Icons.done, color: Colors.white38, size: 14);
      case MessageStatus.delivered: return const Icon(Icons.done_all, color: Colors.white38, size: 14);
      case MessageStatus.seen: return const Icon(Icons.done_all, color: Colors.greenAccent, size: 14);
      case MessageStatus.error: return const Icon(Icons.error_outline, color: Colors.redAccent, size: 14);
    }
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, top: 5), // Added padding to prevent "daba hua" look
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 3, backgroundColor: Colors.white38),
              SizedBox(width: 4),
              CircleAvatar(radius: 3, backgroundColor: Colors.white38),
              SizedBox(width: 4),
              CircleAvatar(radius: 3, backgroundColor: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          if (_replyingToMessage != null) _buildReplyInputBar(),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showMediaPopup(),
                child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: Colors.orangeAccent, size: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 50,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25)),
                  child: TextField(
                    controller: _messageController,
                    onChanged: (val) => _handleTypingStatus(),
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(hintText: 'Type message...', hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildSendOrMicButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyInputBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 4, height: 35, color: Colors.orangeAccent),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_replyingToMessage!.isMe ? 'You' : widget.name, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(_replyingToMessage!.text ?? 'Media', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          IconButton(icon: const Icon(Icons.close, size: 20, color: Colors.white38), onPressed: () => setState(() => _replyingToMessage = null)),
        ],
      ),
    );
  }

  Widget _buildSendOrMicButton() {
    bool hasText = _messageController.text.trim().isNotEmpty;
    return GestureDetector(
      onLongPress: hasText ? null : () => _showVoiceRecorderModal(),
      onTap: hasText ? _sendMessage : () => _showVoiceRecorderModal(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
        child: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, color: Colors.black, size: 24),
      ),
    );
  }

  void _handleTypingStatus() {
    if (_isBlocked) return; // Don't send socket event if blocked
    
    SocketService().emit('typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      SocketService().emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
    });
  }

  // --- POPUPS & MODALS ---

  void _showMediaPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaSelectionModal(
        currentUserPhone: currentUser!['phone'],
        onMediaSelected: (file, type, {String? url}) async {
          if (_isBlocked) {
             final localId = DateTime.now().millisecondsSinceEpoch.toString();
             setState(() {
                _messages.add(ChatMessage(
                  localId: localId,
                  text: type == 'image' ? '📷 Image' : '🎵 Voice Message',
                  imageUrl: url,
                  isMe: true,
                  timestamp: DateTime.now(),
                  status: MessageStatus.error,
                  type: type,
                ));
             });
             _scrollToBottom();
             return;
          }

          if (url != null) {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPreviewPage(imageUrl: url)));
            if (result != null) {
              _chatRepository.sendMessage(
                senderPhone: currentUser!['phone'],
                receiverPhone: widget.receiverPhone,
                senderName: currentUser!['name'] ?? 'User',
                message: '',
                imageUrl: url,
                type: 'image',
                isViewOnce: result['isViewOnce']
              );
            }
          } else {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPreviewPage(file: file)));
            if (result != null) _uploadMedia(file, type, isViewOnce: result['isViewOnce']);
          }
        }
      )
    );
  }

  void _showVoiceRecorderModal() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: false,
      builder: (_) => VoiceRecorderModal(onSend: (path) => _uploadMedia(File(path), 'audio'))
    );
  }

  void _showContextMenu(ChatMessage msg) {
    if (msg.type == 'block_event') return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
              ListTile(leading: const Icon(Icons.reply_rounded, color: Colors.orangeAccent), title: const Text('Reply', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() => _replyingToMessage = msg); }),
              ListTile(leading: const Icon(Icons.copy_rounded, color: Colors.orangeAccent), title: const Text('Copy', style: TextStyle(color: Colors.white)), onTap: () { Clipboard.setData(ClipboardData(text: msg.text ?? '')); Navigator.pop(context); }),
              if (msg.isMe && msg.type == 'text' && !msg.isDeletedForEveryone) ListTile(leading: const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent), title: const Text('Edit', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() { _editingMessageId = msg.id; _messageController.text = msg.text ?? ''; }); }),
              if (msg.isMe && !msg.isDeletedForEveryone) ListTile(leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent), title: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.pop(context); _confirmDeleteForEveryone(msg); }),
              if (!msg.isDeletedForEveryone) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.white54), title: const Text('Delete for me', style: TextStyle(color: Colors.white54)), onTap: () { Navigator.pop(context); _confirmDelete(msg); }),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteForEveryone(ChatMessage msg) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Delete for everyone?', style: TextStyle(color: Colors.white)),
      content: const Text('This message will be deleted for everyone in this chat.', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(onPressed: () {
          SocketService().emit('delete_message_for_everyone', {'messageId': msg.id, 'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
          Navigator.pop(context);
        }, child: const Text('DELETE FOR EVERYONE', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  void _confirmDelete(ChatMessage msg) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Delete Message?', style: TextStyle(color: Colors.white)),
      content: const Text('This message will be removed from your chat history.', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(onPressed: () {
          // Local Delete: Remove from UI instantly
          setState(() {
            _messages.removeWhere((m) => m.id == msg.id || (m.localId != null && m.localId == msg.localId));
          });
          
          // Server Notify (Optional but good for persistence if server supports it)
          SocketService().emit('delete_message', {
            'messageId': msg.id, 
            'myPhone': currentUser!['phone'], 
            'otherPhone': widget.receiverPhone
          });

          Navigator.pop(context);
        }, child: const Text('DELETE', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  // --- HELPERS ---

  bool _isSameDay(DateTime d1, DateTime d2) => d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  
  String _getFormattedDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(date);
  }
}

// --- SUB-WIDGETS ---

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
      final photos = await ChatRepository().getRecentPhotos(widget.currentUserPhone);
      if (mounted) setState(() => _recentPhotos = photos);
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 25),
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
            ],
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Photos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () => setState(() => _isEditMode = !_isEditMode), child: Text(_isEditMode ? 'Done' : 'Edit', style: const TextStyle(color: Colors.orangeAccent))),
            ],
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentPhotos.length,
              itemBuilder: (_, i) => _buildRecentItem(_recentPhotos[i]),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: color, size: 28)),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _buildRecentItem(dynamic p) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () { if (!_isEditMode) { Navigator.pop(context); widget.onMediaSelected(File(''), 'image', url: p['imageUrl']); } },
          child: Container(
            width: 80, height: 100, margin: const EdgeInsets.only(right: 10),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: p['imageUrl'], fit: BoxFit.cover)),
          ),
        ),
        if (_isEditMode) Positioned(
          top: 5, 
          right: 15, 
          child: GestureDetector(
            onTap: () async {
              final confirmed = await _showDeleteConfirmation();
              if (confirmed) {
                final success = await ChatRepository().deleteRecentPhoto(widget.currentUserPhone, p['imageUrl']);
                if (success) {
                  _fetchRecentPhotos(); // UI Refresh
                }
              }
            }, 
            child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white))
          )
        ),
      ],
    );
  }

  Future<bool> _showDeleteConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Photo?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete the photo.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    ) ?? false;
  }
}

class VoiceRecorderModal extends StatefulWidget {
  final Function(String) onSend;
  const VoiceRecorderModal({super.key, required this.onSend});
  @override
  State<VoiceRecorderModal> createState() => _VoiceRecorderModalState();
}

class _VoiceRecorderModalState extends State<VoiceRecorderModal> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _seconds = 0;
  Timer? _timer;
  bool _isCancelled = false;
  double _dragX = 0;
  final double _cancelThreshold = -100.0; // Left swipe threshold to cancel

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _seconds++));
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (await Permission.microphone.request().isGranted) {
      final dir = await getApplicationDocumentsDirectory();
      final p = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: p);
      _startTimer();
      setState(() {
        _isRecording = true;
        _isCancelled = false;
        _dragX = 0;
      });
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _stopAndSend() async {
    final path = await _recorder.stop();
    _stopTimer();
    setState(() => _isRecording = false);

    if (!_isCancelled && path != null) {
      final duration = _seconds;
      if (duration < 1) {
        // Too short
        return;
      }
      widget.onSend(path);
      Navigator.pop(context);
      HapticFeedback.lightImpact();
    } else {
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRecording) const BlinkingDotRed(),
              const SizedBox(width: 8),
              Text(
                '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
              if (_isRecording)
                Positioned(
                  left: 0,
                  right: 80,
                  child: Opacity(
                    opacity: (1 - (_dragX.abs() / _cancelThreshold.abs())).clamp(0.0, 1.0),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back_ios, color: Colors.white24, size: 16),
                        Text(' Slide to cancel', style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                ),
              GestureDetector(
                onLongPressStart: (_) => _start(),
                onLongPressEnd: (_) => _stopAndSend(),
                onLongPressMoveUpdate: (details) {
                  setState(() {
                    _dragX = details.localPosition.dx;
                    if (_dragX < _cancelThreshold) {
                      _isCancelled = true;
                    } else {
                      _isCancelled = false;
                    }
                  });
                },
                child: Transform.scale(
                  scale: _isRecording ? 1.2 : 1.0,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: _isCancelled 
                        ? Colors.red.withOpacity(0.5) 
                        : (_isRecording ? Colors.red : Colors.orangeAccent),
                    child: Icon(
                      _isCancelled ? Icons.delete_outline : (_isRecording ? Icons.mic : Icons.mic_none),
                      color: Colors.black,
                      size: 35,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            _isCancelled ? 'Release to cancel' : 'Hold to record, release to send',
            style: TextStyle(
              color: _isCancelled ? Colors.redAccent : Colors.white38,
              fontSize: 14,
              fontWeight: _isCancelled ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class BlinkingDotRed extends StatefulWidget {
  const BlinkingDotRed({super.key});
  @override
  State<BlinkingDotRed> createState() => _BlinkingDotRedState();
}

class _BlinkingDotRedState extends State<BlinkingDotRed> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)));
  }
}


class AudioPlayerWidget extends StatefulWidget {
  final String url; final bool isMe;
  const AudioPlayerWidget({super.key, required this.url, required this.isMe});
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer(); 
  bool _isPlaying = false; 
  Duration _duration = Duration.zero; 
  Duration _position = Duration.zero;

  @override
  void initState() { 
    super.initState(); 
    _player.onDurationChanged.listen((d) => setState(() => _duration = d)); 
    _player.onPositionChanged.listen((p) => setState(() => _position = p)); 
    _player.onPlayerComplete.listen((_) => setState(() => _isPlaying = false)); 
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: widget.isMe ? Colors.black : Colors.orangeAccent, size: 32),
          onPressed: () async {
            if (_isPlaying) { await _player.pause(); setState(() => _isPlaying = false); }
            else { await _player.play(UrlSource(widget.url)); setState(() => _isPlaying = true); }
          }
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 100, height: 3, color: Colors.white24, child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0, child: Container(color: widget.isMe ? Colors.black : Colors.orangeAccent))),
          const SizedBox(height: 4),
          Text('${_position.inSeconds}s / ${_duration.inSeconds}s', style: TextStyle(color: widget.isMe ? Colors.black54 : Colors.white54, fontSize: 10)),
        ])
      ],
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final bool isViewOnce;
  const FullScreenImageViewer({super.key, required this.imageUrl, this.isViewOnce = false});
  @override
  Widget build(BuildContext context) { 
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: true, // Always show back button so user can exit
      ), 
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: imageUrl, 
            placeholder: (_, __) => const CircularProgressIndicator(color: Colors.orangeAccent)
          )
        )
      ),
    ); 
  }
}

class MediaPreviewPage extends StatelessWidget {
  final File? file;
  final String? imageUrl;
  const MediaPreviewPage({super.key, this.file, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: file != null 
                  ? Image.file(file!) 
                  : CachedNetworkImage(
                      imageUrl: imageUrl!, 
                      placeholder: (_, __) => const CircularProgressIndicator(color: Colors.orangeAccent)
                    )
              )
            ),
            Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {'isViewOnce': true}), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent, 
                  minimumSize: const Size(double.infinity, 50), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
                ), 
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center, 
                  children: [
                    Text('Send as View Once ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
                    Icon(Icons.looks_one, color: Colors.black, size: 18)
                  ]
                )
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {'isViewOnce': false}), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, 
                  minimumSize: const Size(double.infinity, 50), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
                ), 
                child: const Text('Send Normal', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
              ),
            ])),
          ],
        ),
      ),
    );
  }
}
