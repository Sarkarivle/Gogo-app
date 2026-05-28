import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';
import '../services/chat_repository.dart';
import '../services/premium_service.dart';
import '../services/api_service.dart';
import '../services/permission_manager.dart';
import '../services/notification_service.dart';
import 'chat_settings_screen.dart';
import 'profile_detail_screen.dart';
import '../widgets/chat_widgets.dart';

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

  static Future<void> navigate(BuildContext context, {
    required String name,
    required String receiverPhone,
    required String distance,
    required String position,
  }) async {
    await PermissionManager().handleChatEntryOnboarding(context);
    
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatPage(
        name: name,
        receiverPhone: receiverPhone,
        distance: distance,
        position: position,
      ),
    ));
  }

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _AnimatedMessageWrapper extends StatefulWidget {
  final Widget child;
  const _AnimatedMessageWrapper({required this.child});

  @override
  State<_AnimatedMessageWrapper> createState() => _AnimatedMessageWrapperState();
}

class _AnimatedMessageWrapperState extends State<_AnimatedMessageWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 400)
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _animation,
      axisAlignment: -1.0, // This creates the "pushing" effect from bottom
      child: FadeTransition(
        opacity: _animation,
        child: widget.child,
      ),
    );
  }
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
  bool _isRecipientDeactivated = false;
  String? _blockerPhone;
  Map<String, dynamic>? currentUser;
  Timer? _typingTimer;
  final ValueNotifier<bool> _isOtherUserTyping = ValueNotifier(false);
  Timer? _hideTypingTimer;
  final ValueNotifier<String?> _firstUnreadMessageId = ValueNotifier(null);
  Timer? _unreadTagTimer;
  
  StreamSubscription? _socketMsgSub;
  StreamSubscription? _socketEventSub;

  String? _editingMessageId;
  ChatMessage? _replyingToMessage;

  final ChatRepository _chatRepository = ChatRepository();

  final Set<String> _animatedMessageIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_onTextChanged);
    _loadUserAndHistory();
    _listenToSocket();
    
    _scrollController.addListener(_onScroll);
    SocketService().typingUsers.addListener(_handleTypingScroll);
    SocketService().typingUsers.addListener(_updateOtherUserTyping);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == ui.AppLifecycleState.resumed) {
      // Re-join room and refresh history to get missed real-time messages
      final roomId = _getRoomId();
      SocketService().joinRoom(roomId);
      _fetchChatHistory(forceRefresh: true);
      _chatRepository.markChatSeen(currentUser!['phone'], widget.receiverPhone);
    }
  }

  void _initializeFirstUnread() {
    try {
      final firstUnread = _messages.firstWhere((m) => !m.isMe && !m.isOpened && !m.isDeletedForEveryone);
      _firstUnreadMessageId.value = firstUnread.id;
      
      _unreadTagTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _firstUnreadMessageId.value = null;
      });
    } catch (_) {
      _firstUnreadMessageId.value = null;
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore && _hasMoreHistory && !_isLoadingHistory) {
      _fetchChatHistory(loadMore: true);
    }
  }

  void _handleTypingScroll() {
    // In reversed list, the bottom is at pixels 0.
    // Typing indicator is at index 0. So it naturally appears without scrolling.
  }

  @override
  void dispose() {
    SocketService().typingUsers.removeListener(_handleTypingScroll);
    SocketService().typingUsers.removeListener(_updateOtherUserTyping);
    SocketService().leaveRoom();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _hideTypingTimer?.cancel();
    _unreadTagTimer?.cancel();
    _socketMsgSub?.cancel();
    _socketEventSub?.cancel();
    super.dispose();
  }

  void _updateOtherUserTyping() {
    if (!mounted) return;
    final bool isTyping = SocketService().typingUsers.value[widget.receiverPhone] ?? false;
    if (isTyping) {
      _hideTypingTimer?.cancel();
      _isOtherUserTyping.value = true;
    } else {
      _isOtherUserTyping.value = false;
    }
  }

  Future<void> _loadUserAndHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      if (mounted) {
        setState(() {
          currentUser = jsonDecode(userData);
        });
      }
      final roomId = _getRoomId();
      SocketService().joinRoom(roomId);
      
      _chatRepository.markChatSeen(currentUser!['phone'], widget.receiverPhone);
      NotificationService.clearUnreadForSender(widget.receiverPhone);
    }
    
    // Step 1: Instant load from cache (no force refresh)
    await _fetchChatHistory(forceRefresh: false);
    
    // Step 2: Background refresh (force refresh)
    // This will update messages, block status and deactivated status in one call
    _fetchChatHistory(forceRefresh: true);
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
            final idxDelivered = _messages.indexWhere((m) => m.id != null && m.id.toString() == data['messageId']?.toString());
            if (idxDelivered != -1) {
              setState(() {
                _messages[idxDelivered].status = MessageStatus.delivered;
              });
            }
            break;
          case 'pending_messages_delivered':
          case 'global_delivery_update':
            // Update all my outgoing messages to delivered if the other person just came online
            if (data ['phone'] == widget.receiverPhone || data['receiverPhone'] == widget.receiverPhone) {
              setState(() {
                for (var m in _messages) {
                  if (m.isMe && m.status == MessageStatus.sent) {
                    m.status = MessageStatus.delivered;
                  }
                }
              });
            }
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
            for (var m in _messages) {
              if (m.isMe) m.status = MessageStatus.seen;
            }
            break;
          case 'message_deleted':
            final msgId = (data['messageId'] ?? data['_id'])?.toString();
            final isEveryone = data['isDeletedForEveryone'] ?? false;
            if (msgId == null) return;

            setState(() {
              if (isEveryone) {
                final idx = _messages.indexWhere((m) => m.id != null && m.id.toString() == msgId.toString());
                if (idx != -1) {
                  _messages[idx].isDeletedForEveryone = true;
                  _messages[idx].text = "This message was deleted";
                  _messages[idx].imageUrl = null;
                  _messages[idx].audioUrl = null;
                  _messages[idx].status = MessageStatus.sent;
                } else {
                  _fetchChatHistory(); 
                }
              } else {
                _messages.removeWhere((m) => m.id?.toString() == msgId.toString() || (m.localId != null && m.localId.toString() == data['localId']?.toString()));
              }
            });
            break;
          case 'message_edited':
            final msgIdEdit = (data['messageId'] ?? data['_id'])?.toString();
            if (msgIdEdit == null) return;

            setState(() {
              final idx = _messages.indexWhere((m) => m.id != null && m.id.toString() == msgIdEdit.toString());
              if (idx != -1) {
                _messages[idx].text = data['newText'];
                _messages[idx].isEdited = true;
              }
            });
            break;
          case 'chat_status_update':
            _fetchChatHistory(forceRefresh: true);
            break;
          case 'user_deactivated':
            if (data['phone'] == widget.receiverPhone) {
              setState(() => _isRecipientDeactivated = true);
            }
            break;
          case 'user_reactivated':
            if (data['phone'] == widget.receiverPhone) {
              setState(() {
                _isRecipientDeactivated = false;
                _messages.add(ChatMessage(
                  id: 'reactivation_${DateTime.now().millisecondsSinceEpoch}',
                  text: '${widget.name} is active again',
                  isMe: false,
                  timestamp: DateTime.now(),
                  type: 'reactivation_event'
                ));
              });
              _scrollToBottom();
            }
            break;
        }
      });
    });
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;
    
    final newMessage = ChatMessage.fromJson(data, currentUser?['phone'] ?? '');
    
    setState(() {
      // 1. If it's my message, find the optimistic version and update/replace it
      if (newMessage.isMe) {
        final existingIndex = _messages.indexWhere((m) => 
          (m.localId != null && m.localId.toString() == data['localId']?.toString()) ||
          (m.id != null && m.id == newMessage.id)
        );
        
        if (existingIndex != -1) {
          final existing = _messages[existingIndex];
          newMessage.localFilePath = existing.localFilePath;
          _messages[existingIndex] = newMessage;
          return;
        }
      }
      
      // 2. Avoid duplicates
      final dupIndex = _messages.indexWhere((m) => m.id != null && m.id == newMessage.id);
      if (dupIndex != -1) {
        _messages[dupIndex] = newMessage;
      } else {
        _messages.insert(0, newMessage);
        // Ensure sorting: Newest first (index 0)
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        if (!newMessage.isMe) {
          _hideTypingTimer?.cancel();
          _isOtherUserTyping.value = false;
          SocketService().setTyping(widget.receiverPhone, false);
          if (!newMessage.isViewOnce) {
            _chatRepository.markOpened(newMessage.id!, currentUser!['phone'], widget.receiverPhone);
          }
        }
      }
    });
  }

  Future<void> _fetchChatHistory({bool loadMore = false, bool forceRefresh = false}) async {
    if (currentUser == null || (loadMore && !_hasMoreHistory)) return;
    
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else if (!forceRefresh) {
      setState(() => _isLoadingHistory = true);
    }

    try {
      final page = loadMore ? _currentHistoryPage + 1 : 1;
      final result = await _chatRepository.getChatHistory(
        myPhone: currentUser!['phone'],
        otherPhone: widget.receiverPhone,
        page: page,
        limit: 30,
        forceRefresh: forceRefresh,
      );
      
      final List<ChatMessage> newMsgs = result['messages'] ?? [];
      
      // Prevent animation for history messages
      for (var m in newMsgs) {
        if (m.id != null) _animatedMessageIds.add(m.id!);
        if (m.localId != null) _animatedMessageIds.add(m.localId!);
      }

      if (mounted) {
        setState(() {
          if (page == 1) {
            // Update metadata if available (usually on first page load/refresh)
            if (result.containsKey('isBlocked')) {
              _isBlocked = result['isBlocked'];
              _blockerPhone = result['blockerPhone'];
            }
            if (result.containsKey('isPartnerDeactivated')) {
              _isRecipientDeactivated = result['isPartnerDeactivated'];
            }
          }

          if (loadMore) {
            _messages.addAll(newMsgs);
            _currentHistoryPage++;
          } else {
            // Merge logic: keep local "sending" messages that are not yet in the fresh history
            final localMsgs = _messages.where((m) => m.status == MessageStatus.sending || m.status == MessageStatus.error || m.localId != null).toList();
            _messages.clear();
            _messages.addAll(newMsgs);
            for (var lm in localMsgs) {
              if (!_messages.any((m) => m.localId == lm.localId || (m.id != null && m.id == lm.id))) {
                _messages.add(lm);
              }
            }
            // Sort: Newest first for reversed list
            _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _currentHistoryPage = 1;
          }
          _hasMoreHistory = newMsgs.length >= 30;
        });

        if (!loadMore && page == 1) {
          _initializeFirstUnread();
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

  String _getRoomId() {
    List<String> ids = [currentUser?['phone'] ?? 'Me', widget.receiverPhone];
    ids.sort();
    return ids.join('_');
  }

  bool _isSending = false;

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || currentUser == null || _isSending) return;

    setState(() => _isSending = true);

    final sendContext = context;
    final isPremium = await PremiumService().checkPremiumAndRedirect(sendContext);
    if (!isPremium) {
      setState(() => _isSending = false);
      return;
    }
    if (!sendContext.mounted) {
      setState(() => _isSending = false);
      return;
    }

    if (_editingMessageId != null) {
      _chatRepository.editMessage(_editingMessageId!, text, currentUser!['phone'], widget.receiverPhone);
      setState(() {
        _editingMessageId = null;
        _isSending = false;
      });
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
      _messages.insert(0, optimisticMsg);
      _replyingToMessage = null;
      _messageController.clear();
      // Reset _isSending immediately after clearing controller so Mic/Send UI toggles fast
      _isSending = false;
    });

    _scrollToBottom();

    if (_isBlocked) return;

    _typingTimer?.cancel();
    _typingTimer = null;
    SocketService().emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});

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
          setState(() {
            if (ack['success'] == true) {
               if (ack['messageId'] != null) optimisticMsg.id = ack['messageId'];
               optimisticMsg.status = MessageStatus.sent;
            } else {
              optimisticMsg.status = MessageStatus.error;
              if (ack['isBlocked'] == true) {
                _isBlocked = true;
                _blockerPhone = ack['blockerPhone'];
              }
            }
          });
        }
      }
    );
  }

  Future<void> _uploadMedia(File file, String type, {bool isViewOnce = false}) async {
    if (currentUser == null) return;

    final localId = "msg_${DateTime.now().millisecondsSinceEpoch}";
    final optimisticMsg = ChatMessage(
      localId: localId,
      text: type == 'image' ? '📷 Image' : (type == 'audio' ? '🎵 Voice Message' : '🎥 Video'),
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: type,
      localFilePath: file.path,
      isViewOnce: isViewOnce,
    );

    setState(() {
      _messages.insert(0, optimisticMsg);
    });

    _scrollToBottom();

    try {
      if (!file.existsSync()) throw Exception("File missing");
      
      final uploadContext = context;
      final isPremium = await PremiumService().checkPremiumAndRedirect(uploadContext);
      if (!isPremium) {
        if (mounted) setState(() => optimisticMsg.status = MessageStatus.error);
        return;
      }
      if (!uploadContext.mounted) return;

      final url = await _chatRepository.uploadMedia(file, currentUser!['phone'], type);
      if (url == null) throw Exception("Upload failed");

      if (mounted) {
        setState(() {
          optimisticMsg.imageUrl = (type == 'image' || type == 'video') ? url : null;
          optimisticMsg.audioUrl = type == 'audio' ? url : null;
        });
      }
      
      _typingTimer?.cancel();
      _typingTimer = null; 
      SocketService().emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});

      _chatRepository.sendMessage(
        senderPhone: currentUser!['phone'],
        receiverPhone: widget.receiverPhone,
        senderName: currentUser!['name'] ?? 'User',
        message: '',
        imageUrl: (type == 'image' || type == 'video') ? url : null,
        audioUrl: type == 'audio' ? url : null,
        type: type,
        localId: localId,
        isViewOnce: isViewOnce,
        ack: (ack) {
          if (mounted && ack != null) {
            setState(() {
              if (ack['success'] == true) {
                 if (ack['messageId'] != null) optimisticMsg.id = ack['messageId'];
                 optimisticMsg.status = MessageStatus.sent;
              } else {
                optimisticMsg.status = MessageStatus.error;
              }
            });
          }
        }
      );
    } catch (e) {
      if (mounted) {
        setState(() => optimisticMsg.status = MessageStatus.error);
        _showError(e.toString());
      }
    }
  }

  void _showError(String message) {
    final errorContext = context;
    if (!errorContext.mounted) return;
    ScaffoldMessenger.of(errorContext).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  void _scrollToBottom({bool immediate = false}) {
    if (!_scrollController.hasClients) return;
    if (immediate) {
      _scrollController.jumpTo(0);
    } else {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

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
      leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent), onPressed: () => Navigator.pop(context)),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailPage(
          name: widget.name, 
          phone: widget.receiverPhone, 
          distance: widget.distance, 
          city: '', // Don't pass 'Unknown'
          area: '', 
          age: 18, 
          position: widget.position, 
          havePlace: '', 
          showMessageButton: false
        ))),
        child: Row(
          children: [
            CircleAvatar(radius: 18, backgroundColor: Colors.white10, child: const Icon(Icons.person, color: Colors.white54, size: 20)),
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
                      String cleanDist = widget.distance
                          .replaceAll(' away', '')
                          .replaceAll('Within ', '')
                          .replaceAll('Under ', '');
                      return Row(
                        children: [
                          Text(cleanDist, style: const TextStyle(fontSize: 11, color: Colors.white54)),
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
        IconButton(icon: const Icon(Icons.call_outlined, color: Colors.orangeAccent), onPressed: () => _initiateCall(isVideo: false)),
        IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.orangeAccent), onPressed: () => _initiateCall(isVideo: true)),
        IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent), onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSettingsPage(name: widget.name, phone: widget.receiverPhone)));
          if (result == true) _loadUserAndHistory();
        })
      ],
    );
  }

  Widget _buildMessageList() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isOtherUserTyping,
      builder: (context, isTyping, _) {
        final int itemCount = _messages.length + 
                             (isTyping ? 1 : 0) + 
                             (_isLoadingMore ? 1 : 0) + 
                             (_isRecipientDeactivated ? 1 : 0) +
                             (_messages.isEmpty ? 1 : 0);

        return ListView.builder(
          controller: _scrollController,
          reverse: true, // IMPORTANT: Reverse for chat feel
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // 1. Typing Indicator & Deactivated (Bottom of reversed list = Start of visual)
            if (isTyping && index == 0) return const TypingIndicator();
            
            int msgIndex = isTyping ? index - 1 : index;
            if (_isRecipientDeactivated && msgIndex == 0) return _buildDeactivatedSystemBubble();
            
            if (_isRecipientDeactivated) msgIndex--;
            
            // 2. Main Messages
            if (msgIndex >= 0 && msgIndex < _messages.length) {
              final msg = _messages[msgIndex];
              final bool isFirst = msgIndex == _messages.length - 1;
              
              // Date Header Logic
              bool showDateHeader = false;
              if (isFirst) {
                showDateHeader = true;
              } else {
                showDateHeader = !_isSameDay(_messages[msgIndex + 1].timestamp, msg.timestamp);
              }

              final String msgKey = msg.id ?? msg.localId ?? '';
              final bool shouldAnimate = msgKey.isNotEmpty && !_animatedMessageIds.contains(msgKey);
              
              // Grouping Logic: Show time only for the last message in a minute-group
              bool showTime = true;
              bool isSameGroupAsNext = false; // Next visually (index - 1)
              if (msgIndex > 0) {
                isSameGroupAsNext = _isSameMinute(_messages[msgIndex - 1].timestamp, msg.timestamp) && 
                                    _messages[msgIndex - 1].isMe == msg.isMe;
                if (isSameGroupAsNext) showTime = false;
              }

              Widget bubble = _buildMessageBubble(msg, showTime: showTime, isSameGroupAsNext: isSameGroupAsNext);
              
              if (shouldAnimate) {
                _animatedMessageIds.add(msgKey);
                bubble = _AnimatedMessageWrapper(child: bubble);
              }

              return Column(
                children: [
                  if (showDateHeader) _buildDateHeader(msg.timestamp),
                  if (isFirst) _buildSafetyWarning(),
                  bubble,
                ],
              );
            }

            // 3. Loading More (Top of reversed list = End of visual)
            if (_isLoadingMore && index == itemCount - 1) {
              return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)));
            }

            if (_messages.isEmpty && index == 0) return _buildSafetyWarning();

            return const SizedBox.shrink();
          },
        );
      }
    );
  }

  Widget _buildSafetyWarning() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 30),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.1), width: 1),
        ),
        child: const Column(
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.security_rounded, color: Colors.orangeAccent, size: 14), SizedBox(width: 8), Text("Keep your community safe", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5))]),
            SizedBox(height: 6),
            Text("If any user asks for money, please report them immediately using the safety tools.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w500, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, {bool showTime = true, bool isSameGroupAsNext = false}) {
    // 1. New Unread Message Tag Logic
    return ValueListenableBuilder<String?>(
      valueListenable: _firstUnreadMessageId,
      builder: (context, firstUnreadId, child) {
        bool isFirstUnread = firstUnreadId != null && msg.id == firstUnreadId;
        return _buildBubbleContentWithTag(msg, isFirstUnread, firstUnreadId, showTime: showTime, isSameGroupAsNext: isSameGroupAsNext);
      },
    );
  }

  Widget _buildBubbleContentWithTag(ChatMessage msg, bool isFirstUnread, String? firstUnreadId, {bool showTime = true, bool isSameGroupAsNext = false}) {
    if (msg.isDeletedForEveryone) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_flipped, color: Colors.white24, size: 14),
              const SizedBox(width: 8),
              Text(
                msg.isMe ? "You deleted this message" : "This message was deleted",
                style: const TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      );
    }

    Widget bubbleContent;
    if (msg.type == 'block_event' || msg.type == 'unblock_event' || msg.type == 'reactivation_event') {
      bubbleContent = Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: msg.type == 'block_event' ? Colors.red.withValues(alpha: 0.1) : (msg.type == 'unblock_event' || msg.type == 'reactivation_event' ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)), 
            borderRadius: BorderRadius.circular(20)
          ),
          child: Text(
            msg.type == 'block_event' ? (msg.isMe ? 'You blocked ${widget.name}' : 'You were blocked') : (msg.type == 'unblock_event' ? 'Chat Unblocked' : msg.text!),
            style: TextStyle(color: msg.type == 'block_event' ? Colors.redAccent : Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (msg.type == 'call_log') {
      bubbleContent = _buildCallLogBubble(msg);
    } else {
      bubbleContent = Padding(
        padding: EdgeInsets.only(bottom: isSameGroupAsNext ? 4 : 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18), 
                      topRight: const Radius.circular(18), 
                      bottomLeft: Radius.circular(msg.isMe ? 18 : (isSameGroupAsNext ? 5 : 0)), 
                      bottomRight: Radius.circular(msg.isMe ? (isSameGroupAsNext ? 5 : 0) : 18)
                    ),
                  ),
                  child: _buildBubbleContent(
                    msg, 
                    timeWidget: (showTime || (msg.isMe && msg.status != MessageStatus.seen)) 
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showTime)
                              Text(
                                DateFormat('h:mm a').format(msg.timestamp), 
                                style: TextStyle(color: msg.isMe ? Colors.black45 : Colors.white38, fontSize: 9)
                              ),
                            if (msg.isMe && (showTime || msg.status != MessageStatus.seen)) ...[
                              const SizedBox(width: 4),
                              _buildStatusIcon(msg.status, size: 12, color: msg.isMe ? Colors.black45 : null)
                            ]
                          ],
                        )
                      : null
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isFirstUnread) {
      return Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: firstUnreadId != null 
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.orangeAccent.withValues(alpha: 0.2), indent: 20, endIndent: 10)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3), width: 0.5),
                        ),
                        child: const Text(
                          "New Unread Messages",
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.orangeAccent.withValues(alpha: 0.2), indent: 10, endIndent: 20)),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
          ),
          bubbleContent,
        ],
      );
    }
    return bubbleContent;
  }

  Widget _buildBubbleContent(ChatMessage msg, {Widget? timeWidget}) {
    if (msg.isViewOnce) return _buildViewOnceImage(msg, timeWidget: timeWidget);

    if (msg.type == 'audio') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AudioPlayerWidget(url: msg.audioUrl ?? msg.localFilePath ?? '', isMe: msg.isMe),
          ?timeWidget,
        ],
      );
    } else if (msg.type == 'image' || msg.type == 'video' || (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) || (msg.localFilePath != null && msg.type != 'audio')) {
      return Stack(
        children: [
          _buildImageContent(msg),
          if (timeWidget != null) Positioned(bottom: 4, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)), child: timeWidget)),
        ],
      );
    }
    
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: 4,
      children: [
        Text(msg.text ?? '', style: TextStyle(color: msg.isMe ? Colors.black : Colors.white, fontSize: 15, height: 1.3)),
        if (timeWidget != null) Padding(padding: const EdgeInsets.only(left: 8, bottom: 2), child: timeWidget),
      ],
    );
  }

  Widget _buildImageContent(ChatMessage msg) {
    final bool hasLocalFile = msg.localFilePath != null && File(msg.localFilePath!).existsSync();
    return GestureDetector(
      onTap: () {
        if (msg.imageUrl != null || hasLocalFile) {
           Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: msg.imageUrl ?? '', localFilePath: hasLocalFile ? msg.localFilePath : null)));
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            hasLocalFile 
              ? Image.file(File(msg.localFilePath!), width: 200, height: 200, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image))
              : CachedNetworkImage(imageUrl: ApiService.getSecureUrl(msg.imageUrl), width: 200, height: 200, fit: BoxFit.cover, placeholder: (c, u) => const Center(child: CircularProgressIndicator())),
            if (msg.status == MessageStatus.sending) Container(width: 200, height: 200, color: Colors.black38, child: const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))),
            if (msg.type == 'video') Center(child: CircleAvatar(backgroundColor: Colors.black45, child: const Icon(Icons.play_arrow, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _buildViewOnceImage(ChatMessage msg, {Widget? timeWidget}) {
    if (msg.isMe) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [
          Icon(msg.isOpened ? Icons.done_all : Icons.looks_one_rounded, color: Colors.black, size: 18),
          const SizedBox(width: 8),
          Text(msg.isOpened ? 'Opened' : 'Photo', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
          if (timeWidget != null) Padding(padding: const EdgeInsets.only(left: 8), child: timeWidget),
        ]
      );
    }

    if (msg.isOpened) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.looks_one_rounded, color: Colors.white24, size: 18),
          const SizedBox(width: 10),
          const Text('Opened', style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 14)),
          if (timeWidget != null) Padding(padding: const EdgeInsets.only(left: 8), child: timeWidget),
        ]
      );
    }

    return GestureDetector(
      onTap: () async {
        if (msg.imageUrl == null) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: msg.imageUrl!, isViewOnce: true)));
        _chatRepository.markOpened(msg.id!, currentUser!['phone'], widget.receiverPhone);
        setState(() { 
          msg.isOpened = true; 
          msg.imageUrl = null;
        });
      },
      child: Container(
        width: 160, height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 1.5)
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20), 
          child: Stack(
            alignment: Alignment.center, 
            children: [
              if (msg.imageUrl != null) 
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25), 
                  child: CachedNetworkImage(imageUrl: ApiService.getSecureUrl(msg.imageUrl), fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                ), 
              Container(color: Colors.black.withValues(alpha: 0.4)), 
              Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  const Icon(Icons.looks_one_rounded, color: Colors.white, size: 36), 
                  const SizedBox(height: 10), 
                  const Text('1 PHOTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1))
                ]
              ),
              if (timeWidget != null) Positioned(bottom: 8, right: 10, child: timeWidget),
            ]
          )
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ChatMessage msg) {
    return Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 3, height: 20, color: Colors.orangeAccent), const SizedBox(width: 8), Flexible(child: Text(msg.replyText ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))]));
  }

  Widget _buildStatusIcon(MessageStatus status, {double size = 14, Color? color}) {
    switch (status) {
      case MessageStatus.sending: return SizedBox(width: size - 2, height: size - 2, child: CircularProgressIndicator(strokeWidth: 1.2, color: color ?? Colors.orangeAccent));
      case MessageStatus.sent: return Icon(Icons.done, color: color ?? Colors.white38, size: size);
      case MessageStatus.delivered: return Icon(Icons.done_all, color: color ?? Colors.white38, size: size);
      case MessageStatus.seen: return Icon(Icons.done_all, color: Colors.greenAccent, size: size); // Hamesha green dikhao seen par
      case MessageStatus.error: return Icon(Icons.error_outline, color: color ?? Colors.redAccent, size: size);
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          if (_isBlocked || _isRecipientDeactivated) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_isRecipientDeactivated ? "Account Deactivated" : (_blockerPhone == currentUser?['phone'] ? "You blocked this user" : "Chat Blocked"), style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
          if (_replyingToMessage != null) _buildReplyInputBar(),
          if (_editingMessageId != null) _buildEditInputBar(),
          Row(
            children: [
              GestureDetector(onTap: (_isBlocked || _isRecipientDeactivated) ? null : () => _showMediaPopup(), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: Colors.orangeAccent, size: 28))),
              const SizedBox(width: 12),
              Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), height: 50, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(25)), child: TextField(controller: _messageController, enabled: !_isRecipientDeactivated, onChanged: (v) => _handleTypingStatus(), onSubmitted: (v) => _sendMessage(), style: const TextStyle(color: Colors.white, fontSize: 15), decoration: const InputDecoration(hintText: 'Type message...', hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none)))),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  final text = _messageController.text.trim();
                  if (text.isEmpty) {
                    if (!_isBlocked && !_isRecipientDeactivated) _handleMicClick();
                  } else {
                    _sendMessage();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                  child: ListenableBuilder(
                    listenable: _messageController,
                    builder: (context, child) {
                      final bool showSend = _messageController.text.trim().isNotEmpty;
                      return Icon(
                        showSend ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.black,
                        size: 24,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyInputBar() {
    return Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12)), child: Row(children: [Container(width: 4, height: 35, color: Colors.orangeAccent), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_replyingToMessage!.isMe ? 'You' : widget.name, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)), Text(_replyingToMessage!.text ?? 'Media', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)])), IconButton(icon: const Icon(Icons.close, size: 20, color: Colors.white38), onPressed: () => setState(() => _replyingToMessage = null))]));
  }

  Widget _buildEditInputBar() {
    return Container(
      padding: const EdgeInsets.all(10), 
      margin: const EdgeInsets.only(bottom: 8), 
      decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)), 
      child: Row(
        children: [
          const Icon(Icons.edit_rounded, color: Colors.orangeAccent, size: 18), 
          const SizedBox(width: 12), 
          const Expanded(child: Text("Editing Message", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold))), 
          IconButton(icon: const Icon(Icons.close, size: 20, color: Colors.white38), onPressed: () {
            setState(() {
              _editingMessageId = null;
              _messageController.clear();
            });
          })
        ]
      )
    );
  }

  void _handleMicClick() async {
    final messengerContext = context;
    final status = await Permission.microphone.request();
    if (!messengerContext.mounted) return;
    if (status.isGranted) {
      _showVoiceRecorderModal();
    } else {
      if (!messengerContext.mounted) return;
      showDialog(
        context: messengerContext,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("Microphone Permission", style: TextStyle(color: Colors.white)),
          content: const Text("GoGo needs microphone access so you can record and send voice messages to your friends.", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
            TextButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); }, child: const Text("SETTINGS", style: TextStyle(color: Colors.orangeAccent))),
          ],
        )
      );
    }
  }

  void _showVoiceRecorderModal() {
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.transparent, 
      isScrollControlled: true,
      builder: (_) => VoiceRecorderModal(onSend: (p) => _uploadMedia(File(p), 'audio'))
    );
  }

  void _handleTypingStatus() {
    if (_isBlocked || _isRecipientDeactivated) return;
    
    // Throttle typing emits to once every 2 seconds
    if (_typingTimer == null || !_typingTimer!.isActive) {
       SocketService().emit('typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
       SocketService().emit('stop_typing', {'myPhone': currentUser!['phone'], 'otherPhone': widget.receiverPhone});
    });
  }

  void _initiateCall({required bool isVideo}) async {
    if (_isBlocked) return;
    final callContext = context;
    final isPremium = await PremiumService().checkPremiumAndRedirect(callContext);
    if (!isPremium) return;
    if (!callContext.mounted) return;
    
    if (await PermissionManager().checkAndRequestCallPermissions(callContext, isVideo: isVideo)) {
      CallService().startCall(widget.receiverPhone, widget.name, isVideo: isVideo);
    }
  }

  void _showMediaPopup() async {
    if (currentUser == null) return;
    final mediaContext = context;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: mediaContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaSelectionModal(currentUserPhone: currentUser!['phone'])
    );

    if (!mediaContext.mounted) return;

    if (result != null) {
      final File? file = result['file'];
      final String? type = result['type'];
      final String? url = result['url'];

      if (url != null) {
        final previewRes = await Navigator.push(mediaContext, MaterialPageRoute(builder: (_) => MediaPreviewPage(imageUrl: url)));
        if (!mediaContext.mounted) return;
        if (previewRes != null) {
          final bool isVid = url.toLowerCase().contains('.mp4') || 
                            url.toLowerCase().contains('.mov') || 
                            url.toLowerCase().contains('.avi');
          _chatRepository.sendMessage(
            senderPhone: currentUser!['phone'], 
            receiverPhone: widget.receiverPhone, 
            senderName: currentUser!['name'] ?? 'User', 
            message: '', 
            imageUrl: url, 
            type: isVid ? 'video' : 'image', 
            isViewOnce: previewRes['isViewOnce']
          );
        }
      } else if (file != null && type != null) {
        final previewRes = await Navigator.push(mediaContext, MaterialPageRoute(builder: (_) => MediaPreviewPage(file: file)));
        if (!mediaContext.mounted) return;
        if (previewRes != null) {
          _uploadMedia(file, type, isViewOnce: previewRes['isViewOnce']);
        }
      }
    }
  }

  void _showContextMenu(ChatMessage msg) {
    if (msg.isDeletedForEveryone) return;
    
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.transparent, 
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A), 
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))
        ), 
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const SizedBox(height: 12), 
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: Colors.orangeAccent), 
                title: const Text('Reply', style: TextStyle(color: Colors.white)), 
                onTap: () { Navigator.pop(context); setState(() => _replyingToMessage = msg); }
              ), 
              if (msg.type == 'text') ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.orangeAccent), 
                title: const Text('Copy', style: TextStyle(color: Colors.white)), 
                onTap: () { Clipboard.setData(ClipboardData(text: msg.text ?? '')); Navigator.pop(context); }
              ),
              if (msg.isMe && msg.type == 'text') ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.orangeAccent),
                title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMessageId = msg.id;
                    _messageController.text = msg.text ?? '';
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Delete for Me', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  if (msg.id != null) {
                    _chatRepository.deleteMessage(msg.id!, deleteType: 'me', myPhone: currentUser!['phone'], otherPhone: widget.receiverPhone);
                  }
                  setState(() {
                    _messages.removeWhere((m) => (m.id != null && m.id == msg.id) || (m.localId != null && m.localId == msg.localId));
                  });
                },
              ),
              if (msg.isMe) ListTile(
                leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  if (msg.id != null) {
                    _chatRepository.deleteMessage(msg.id!, deleteType: 'everyone', myPhone: currentUser!['phone'], otherPhone: widget.receiverPhone);
                    setState(() {
                      final idx = _messages.indexWhere((m) => m.id == msg.id);
                      if (idx != -1) {
                        _messages[idx].isDeletedForEveryone = true;
                        _messages[idx].text = "This message was deleted";
                        _messages[idx].imageUrl = null;
                        _messages[idx].audioUrl = null;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
            ]
          )
        )
      )
    );
  }

  Widget _buildCallLogBubble(ChatMessage msg) {
    final isMissed = (msg.metadata?['status'] ?? '') == 'missed';
    return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isMissed ? Icons.phone_missed : Icons.phone, color: isMissed ? Colors.redAccent : Colors.greenAccent, size: 16), const SizedBox(width: 8), Text(msg.text ?? 'Call', style: const TextStyle(color: Colors.white, fontSize: 12))])));
  }

  Widget _buildDateHeader(DateTime date) {
    return Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Text(DateFormat('MMMM d, y').format(date), style: const TextStyle(color: Colors.white70, fontSize: 10)));
  }

  Widget _buildDeactivatedSystemBubble() {
    return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)), child: const Text("Account Deactivated", style: TextStyle(color: Colors.white38, fontSize: 11))));
  }

  bool _isSameDay(DateTime d1, DateTime d2) => d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  bool _isSameMinute(DateTime d1, DateTime d2) => _isSameDay(d1, d2) && d1.hour == d2.hour && d1.minute == d2.minute;
}

class MediaSelectionModal extends StatefulWidget {
  final String currentUserPhone;
  const MediaSelectionModal({super.key, required this.currentUserPhone});
  @override
  State<MediaSelectionModal> createState() => _MediaSelectionModalState();
}

class _MediaSelectionModalState extends State<MediaSelectionModal> {
  List<dynamic> _recentPhotos = [];
  bool _isEditMode = false;
  String? _deletingUrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchRecentPhotos();
  }

  Future<void> _fetchRecentPhotos() async {
    final photos = await ChatRepository().getRecentPhotos(widget.currentUserPhone);
    if (mounted) setState(() => _recentPhotos = photos);
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
              _buildItem(Icons.camera_alt_rounded, 'Camera', Colors.blueAccent, () async {
                final cameraContext = context;
                final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1200, maxHeight: 1200);
                if (!cameraContext.mounted) return;
                if (f != null) Navigator.pop(cameraContext, {'file': File(f.path), 'type': 'image'});
              }),
              _buildItem(Icons.videocam_rounded, 'Video', Colors.redAccent, () async {
                final videoContext = context;
                final f = await _picker.pickVideo(source: ImageSource.camera);
                if (!videoContext.mounted) return;
                if (f != null) Navigator.pop(videoContext, {'file': File(f.path), 'type': 'video'});
              }),
              _buildItem(Icons.image_rounded, 'Gallery', Colors.greenAccent, () async {
                final galleryContext = context;
                final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1200, maxHeight: 1200);
                if (!galleryContext.mounted) return;
                if (f != null) Navigator.pop(galleryContext, {'file': File(f.path), 'type': 'image'});
              }),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text("Recent Photos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton(onPressed: () => setState(() => _isEditMode = !_isEditMode), child: Text(_isEditMode ? "Done" : "Edit", style: const TextStyle(color: Colors.orangeAccent)))
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _recentPhotos.length, itemBuilder: (c, i) => _buildRecentItem(i)))
        ],
      ),
    );
  }

  Widget _buildRecentItem(int i) {
    final p = _recentPhotos[i];
    final bool isDeleting = _deletingUrl == p['imageUrl'];
    final String url = p['imageUrl'] ?? '';
    final bool isVideo = url.toLowerCase().contains('.mp4') || 
                        url.toLowerCase().contains('.mov') || 
                        url.toLowerCase().contains('.avi');

    return Stack(
      children: [
        GestureDetector(
          onTap: () { 
            if (!_isEditMode && !isDeleting && mounted) {
              Navigator.pop(context, {'url': url}); 
            }
          },
          child: Container(
            width: 80, 
            margin: const EdgeInsets.only(right: 12), 
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15), 
              color: Colors.white10,
              image: isVideo ? null : DecorationImage(
                image: CachedNetworkImageProvider(ApiService.getSecureUrl(url)), 
                fit: BoxFit.cover
              )
            ),
            child: isDeleting 
              ? Container(
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
                  child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))),
                )
              : Stack(
                  children: [
                    if (isVideo) 
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 30)),
                    const Align(
                      alignment: Alignment.topRight, 
                      child: Padding(padding: EdgeInsets.all(5), child: Icon(Icons.lock, color: Colors.white70, size: 14))
                    ),
                  ],
                ),
          )
        ),
        if (_isEditMode && !isDeleting) Positioned(
          top: 0, right: 12, 
          child: GestureDetector(
            onTap: () async { 
              final deleteContext = context;
              final String targetUrl = p['imageUrl'];
              
              setState(() => _deletingUrl = targetUrl);

              // 500ms processing before delete
              await Future.delayed(const Duration(milliseconds: 500));

              final success = await ChatRepository().deleteRecentPhoto(widget.currentUserPhone, targetUrl); 
              
              // 200ms processing after delete
              await Future.delayed(const Duration(milliseconds: 200));

              if (mounted) {
                setState(() {
                  _deletingUrl = null;
                  if (success) {
                    _recentPhotos.removeWhere((p) => p['imageUrl'] == targetUrl);
                  }
                });
                
                if (success) {
                  if (deleteContext.mounted) {
                    ScaffoldMessenger.of(deleteContext).showSnackBar(
                      const SnackBar(
                        content: Text("Image deleted permanently"), 
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      )
                    );
                  }
                } else {
                  _fetchRecentPhotos(); // Refresh if failed
                }
              }
            }, 
            child: CircleAvatar(radius: 12, backgroundColor: Colors.red, child: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white))
          )
        )
      ],
    );
  }

  Widget _buildItem(IconData i, String l, Color c, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Column(children: [Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: c.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 28)), const SizedBox(height: 8), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12))]));
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

  @override
  void dispose() { 
    _timer?.cancel();
    _recorder.dispose(); 
    super.dispose(); 
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(30, 20, 30, MediaQuery.of(context).padding.bottom + 30), 
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E), 
        borderRadius: BorderRadius.vertical(top: Radius.circular(30))
      ), 
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 30),
          if (_isRecording) ...[
            Text(
              '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text("Recording Live...", style: TextStyle(color: Colors.white54, fontSize: 12)),
          ] else
            const Text("Ready to Record", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 30),
              ),
              GestureDetector(
                onTap: () async {
                  if (!_isRecording) {
                    final path = '${(await getTemporaryDirectory()).path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a'; 
                    await _recorder.start(const RecordConfig(), path: path); 
                    _startTimer();
                    if (mounted) setState(() => _isRecording = true);
                  }
                },
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red.withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: _isRecording ? Colors.red : Colors.orangeAccent, width: 2)
                  ),
                  child: Icon(_isRecording ? Icons.mic : Icons.mic_none, size: 40, color: _isRecording ? Colors.red : Colors.orangeAccent),
                ),
              ),
              if (_isRecording)
                IconButton(
                  onPressed: () async {
                    final voiceContext = context;
                    final p = await _recorder.stop(); 
                    _timer?.cancel();
                    if (!voiceContext.mounted) return;
                    setState(() => _isRecording = false); 
                    if (p != null) { 
                      widget.onSend(p); 
                      Navigator.pop(voiceContext);
                    }
                  },
                  icon: const Icon(Icons.send_rounded, color: Colors.orangeAccent, size: 35),
                )
              else
                const SizedBox(width: 48), // Placeholder for symmetry
            ],
          ),
          const SizedBox(height: 20),
          Text(_isRecording ? "Tap Send when finished" : "Tap Mic to start", style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ]
      )
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? localFilePath;
  final bool isViewOnce;
  const FullScreenImageViewer({super.key, required this.imageUrl, this.localFilePath, this.isViewOnce = false});
  @override
  Widget build(BuildContext context) { 
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)), body: Center(child: InteractiveViewer(child: localFilePath != null ? Image.file(File(localFilePath!)) : CachedNetworkImage(imageUrl: ApiService.getSecureUrl(imageUrl), placeholder: (c, u) => const CircularProgressIndicator()))));
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
                      imageUrl: ApiService.getSecureUrl(imageUrl),
                      placeholder: (context, url) => const CircularProgressIndicator(color: Colors.orangeAccent)
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
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            ])),
          ],
        ),
      ),
    );
  }
}

