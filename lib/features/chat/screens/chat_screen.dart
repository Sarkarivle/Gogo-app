import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import 'package:gogo/features/chat/models/chat_message.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/features/call/providers/call_service.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/chat/repositories/chat_realtime_repository.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/services/permission_manager.dart';
import 'package:gogo/core/services/notification_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/profile/repositories/moderation_repository.dart';
import 'package:gogo/core/services/presence_manager.dart';
import 'package:gogo/core/services/typing_manager.dart';
import 'package:gogo/core/services/media_service.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:http/http.dart' as http;
import 'package:gogo/features/chat/screens/chat_settings_screen.dart';
import 'package:gogo/features/chat/screens/media_preview_screen.dart';
import 'package:gogo/features/profile/screens/profile_detail_screen.dart';
import 'package:gogo/features/chat/widgets/chat_widgets.dart';
import 'package:gogo/features/premium/repositories/premium_repository.dart';
import 'package:gogo/features/premium/screens/trial_onboarding_screen.dart';
import 'package:gogo/shared/screens/offer_trial_screen.dart';
import 'package:gogo/features/reviews/widgets/review_modal.dart';
import 'package:gogo/core/utils/phone_utils.dart';
import 'package:gogo/core/services/ad_service.dart';
import 'dart:math';
import 'package:video_player/video_player.dart';

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

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  String? _myPhone;
  String? _myName;
  String? _normalizedReceiverPhone;
  bool _isBlocked = false;
  bool _isPartnerDeactivated = false;
  bool _hasReviewed = false;
  StreamSubscription? _socketSubscription;
  final Map<String, ChatMessage> _messageLookup = {}; // O(1) Lookup for extreme performance

  // Audio Recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isSlidingToCancelNotifier = ValueNotifier<bool>(false);
  bool _isRecorderReady = false;
  Timer? _micHoldTimer;

  // Swipe to reply
  ChatMessage? _replyingTo;

  Timer? _typingTimer;
  bool _isMeTyping = false;
  int _messageCount = 0;
  int _adMessageCounter = 0;
  late int _targetAdCount;
  bool _hasShownReview = false;

  // Receiver Profile Data
  String? _receiverName;
  String? _receiverDistance;
  String? _receiverPosition;
  String? _receiverCity;
  String? _receiverArea;
  int? _receiverAge;
  bool? _isReceiverVerified;
  String? _receiverHavePlace;

  @override
  void initState() {
    super.initState();
    final min = AppConfigService().rewardMinMsg;
    final max = AppConfigService().rewardMaxMsg;
    _targetAdCount = min + Random().nextInt(max - min + 1);
    _normalizedReceiverPhone = PhoneUtils.normalize(widget.receiverPhone) ?? widget.receiverPhone;
    WidgetsBinding.instance.addObserver(this);
    
    _messageController.addListener(_handleTypingStatus);

    // Automatic Pagination (Infinite Scroll)
    _scrollController.addListener(_scrollListener);

    // Centralized Block Listening
    ModerationRepository().blockStatusNotifier.addListener(_syncBlockFromGlobal);

    _initChat();
    _setupSocketListeners();
  }

  void _syncBlockFromGlobal() {
    if (_normalizedReceiverPhone == null) return;
    final bool newStatus = ModerationRepository().isBlocked(_normalizedReceiverPhone!);
    final String? blocker = ModerationRepository().getBlockerPhone(_normalizedReceiverPhone!);
    
    if ((_isBlocked != newStatus || (_isBlocked && blocker != null)) && mounted) {
      debugPrint("📢 [CHAT] Syncing Block from Global: $newStatus by $blocker");
      setState(() {
        _isBlocked = newStatus;
      });
      if (!_isBlocked) _fetchHistory(forceRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 1. Mark seen immediately to turn ticks green for sender
      if (_myPhone != null && _normalizedReceiverPhone != null) {
        ChatRepository().markChatSeen(_myPhone!, _normalizedReceiverPhone!);
      }
      // 2. Refresh history to get any messages received while screen was off
      _fetchHistory(forceRefresh: true);
    }
  }

  Future<void> _initChat() async {
    try {
      // 0. Load receiver profile from cache immediately for instant UI
      final cachedProfile = UserRepository().getCachedProfile(widget.receiverPhone);
      if (cachedProfile != null) {
        _receiverName = cachedProfile['name'];
        _receiverDistance = cachedProfile['distance'] ?? cachedProfile['distanceStr'];
        _receiverPosition = cachedProfile['position'];
        _receiverCity = cachedProfile['city'];
        _receiverArea = cachedProfile['area'];
        
        final rawAge = cachedProfile['age'];
        if (rawAge != null) {
          _receiverAge = rawAge is int ? rawAge : int.tryParse(rawAge.toString()) ?? 0;
        } else if (cachedProfile['dobYear'] != null) {
          final year = int.tryParse(cachedProfile['dobYear'].toString());
          if (year != null && year > 1900) {
            _receiverAge = DateTime.now().year - year;
          }
        }
        
        _isReceiverVerified = cachedProfile['isVerified'] == true;
        _receiverHavePlace = cachedProfile['havePlace'];
      }

      final userData = UserRepository().currentUser ?? await UserRepository().getCurrentUser();
      if (userData != null) {
        _myPhone = PhoneUtils.normalize(userData['phone']);
        _myName = userData['name'];
      }
      
      if (_myPhone == null) {
        debugPrint("🚨 [CHAT] My phone is null, cannot initialize chat");
        setState(() => _isLoading = false);
        return;
      }

      // Set active room
      final String roomId = _getRoomId();
      if (roomId.isNotEmpty) {
        SocketService().joinRoom(roomId);
      }
      
      // Clear notification badges
      NotificationService.clearUnreadForSender(widget.receiverPhone);

      // 1. FIRST LOAD: Fast load from cache (No loader if data exists)
      await _fetchHistory(forceRefresh: false);
      
      // 2. BACKGROUND SYNC: Silent refresh to get latest from server
      if (mounted) {
        _fetchHistory(forceRefresh: true);
        _fetchReceiverProfile();
      }
    } catch (e) {
      debugPrint("🚨 [CHAT] Init Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchReceiverProfile() async {
    try {
      final userData = await UserRepository().fetchProfile(widget.receiverPhone);
      if (userData != null && mounted) {
        setState(() {
          _receiverName = userData['name'];
          _receiverDistance = userData['distance'] ?? userData['distanceStr'];
          _receiverPosition = userData['position'];
          _receiverCity = userData['city'];
          _receiverArea = userData['area'];
          
          final rawAge = userData['age'];
          if (rawAge != null) {
            _receiverAge = rawAge is int ? rawAge : int.tryParse(rawAge.toString()) ?? 0;
          } else if (userData['dobYear'] != null) {
            final year = int.tryParse(userData['dobYear'].toString());
            if (year != null && year > 1900) {
              _receiverAge = DateTime.now().year - year;
            }
          }

          _isReceiverVerified = userData['isVerified'] == true;
          _receiverHavePlace = userData['havePlace'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching receiver profile: $e");
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 600) {
      _fetchHistory(loadMore: true);
    }
  }

  String _getRoomId() {
    if (_myPhone == null || _normalizedReceiverPhone == null) return '';
    List<String> phones = [_myPhone!, _normalizedReceiverPhone!];
    phones.sort();
    return phones.join('_');
  }

  void _addToLookup(ChatMessage m) {
    if (m.id != null) _messageLookup[m.id!] = m;
    if (m.localId != null) _messageLookup[m.localId!] = m;
  }

  void _setupSocketListeners() {
    final String currentRoomId = _getRoomId();
    
    // Switch to Scoped Room Stream for massive CPU savings
    _socketSubscription = ChatRealtimeRepository().getRoomStream(currentRoomId).listen((event) {
      if (!mounted) return;
      
      final dynamic data = event['data'];
      if (data == null) return;

      final String? eventType = event['event'];
      final String? msgType = (data is Map) ? data['type']?.toString() : null;

      // ALWAYS allow block/unblock system events to pass through, regardless of _isBlocked status
      bool isSystemEvent = msgType == 'block_event' || msgType == 'unblock_event';
      
      if (_isBlocked && !isSystemEvent) {
        if (eventType != 'chat_seen_update') {
          return;
        }
      }

      // double check room context for seen update
      bool isMatch = true; 
      if (data is Map && eventType == 'chat_seen_update') {
        final String? byPhone = PhoneUtils.normalize(data['by'] ?? data['viewerPhone']);
        if (byPhone != null && byPhone != _normalizedReceiverPhone) isMatch = false;
      }

      if (!isMatch && eventType != 'message_deleted_for_everyone' && eventType != 'message_deleted') {
        return;
      }

      // Handle Events
      switch (eventType) {
        case 'receive_message':
          _handleReceivedMessage(data);
          break;
        case 'message_delivered':
          _updateMessageStatus(data['localId'] ?? data['messageId'], MessageStatus.delivered);
          break;
        case 'message_opened':
          _updateMessageStatus(data['messageId'], MessageStatus.seen);
          break;
        case 'chat_seen_update':
          _markAllMeMessagesSeen();
          break;
        case 'global_delivery_update':
        case 'pending_messages_delivered':
          _markAllMeMessagesDelivered();
          break;
        case 'message_deleted_for_everyone':
        case 'message_deleted':
          final String? mId = data is Map ? (data['messageId'] ?? data['id']) : data.toString();
          if (data is Map && (data['isDeletedForEveryone'] == true || data['isEveryone'] == true || eventType == 'message_deleted_for_everyone')) {
            _handleDeletedForEveryone(mId);
          } else if (eventType == 'message_deleted') {
            _handleDeleteForMeLocally(mId);
          }
          break;
        case 'message_edited':
          _handleMessageEdited(data['messageId'], data['newText']);
          break;
        case 'chat_status_update':
          if (data['status'] == 'active') {
            _markAllMeMessagesSeen();
          }
          break;
      }
    });
  }

  void _handleReceivedMessage(dynamic data) {
    final newMessage = ChatMessage.fromJson(data, _myPhone!);
    newMessage.isNew = true; // Mark for animation

    final existing = _messageLookup[newMessage.id] ?? _messageLookup[newMessage.localId];

    if (existing == null) {
      setState(() {
        _messageCount++;
        _adMessageCounter++;
        _messages.insert(0, newMessage);
        _addToLookup(newMessage);
        
        // Only animate scroll if at the bottom
        if (_scrollController.hasClients && _scrollController.offset < 100) {
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    } else {
      // Update the existing optimistic message with server-side data
      existing.id = newMessage.id;
      _addToLookup(existing); // Ensure real ID is now in lookup
      
      // Status forward only (handled by setter in ChatMessage)
      existing.status = newMessage.status;
      
      if (newMessage.isViewOnce) existing.isOpened = newMessage.isOpened;
      if (newMessage.audioUrl != null) existing.audioUrl = newMessage.audioUrl;
      if (newMessage.imageUrl != null) existing.imageUrl = newMessage.imageUrl;
    }

    _checkAndShowReviewPopup();
  }

  void _checkAndShowReviewPopup() {
    if (!_hasShownReview && !_hasReviewed && _messageCount >= 10) {
      _hasShownReview = true;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ReviewModal.show(
            context,
            reviewerPhone: _myPhone!,
            reviewerName: _myName ?? 'Me',
            reviewedPhone: _normalizedReceiverPhone ?? widget.receiverPhone,
            reviewedName: widget.name,
          );
        }
      });
    }
  }

  void _updateMessageStatus(String? id, MessageStatus status) {
    if (id == null) return;
    
    final m = _messageLookup[id];
    
    if (m != null) {
      // Update the ValueNotifier directly (Performance: No setState needed)
      m.status = status;
      if ((status == MessageStatus.seen || status == MessageStatus.delivered) && m.isViewOnce) {
        // If it's a view-once and we got a seen/delivered status from server, sync it
        if (status == MessageStatus.seen && !m.isOpened) {
          m.isOpened = true;
          m.imageUrl = null;
          m.audioUrl = null;
        }
      }
    }
  }

  void _markAllMeMessagesSeen() {
    int alreadySeenCount = 0;
    for (var m in _messages) {
      if (m.isMe && !m.isViewOnce) {
        if (m.status != MessageStatus.seen) {
          m.status = MessageStatus.seen;
          alreadySeenCount = 0;
        } else {
          alreadySeenCount++;
          // Optimization: If we hit 15 already-seen messages, stop iterating
          if (alreadySeenCount > 15) break;
        }
      }
    }
  }

  void _markAllMeMessagesDelivered() {
    int alreadyDeliveredCount = 0;
    for (var m in _messages) {
      if (m.isMe) {
        if (m.status == MessageStatus.sent) {
          m.status = MessageStatus.delivered;
          alreadyDeliveredCount = 0;
        } else if (m.status.index >= MessageStatus.delivered.index) {
          alreadyDeliveredCount++;
          if (alreadyDeliveredCount > 15) break;
        }
      }
    }
  }

  void _handleDeletedForEveryone(String? messageId) {
    if (messageId == null) return;
    if (_myPhone != null && _normalizedReceiverPhone != null) {
      ChatRepository().updateMessageDeletionInCache(_myPhone!, widget.receiverPhone, messageId);
    }
    
    final m = _messageLookup[messageId];
    if (m != null) {
      m.isDeletedForEveryone = true;
      m.text = null;
      m.imageUrl = null;
      m.audioUrl = null;
      m.localFilePath = null;
    }
  }

  void _handleDeleteForMeLocally(String? messageId) {
    if (messageId == null) return;
    final m = _messageLookup[messageId];
    if (m == null) return;

    setState(() {
      _messages.remove(m);
      _messageLookup.remove(m.id);
      _messageLookup.remove(m.localId);
      m.dispose(); // Cleanup!
    });
  }

  void _handleMessageEdited(String messageId, String newText) {
    final m = _messageLookup[messageId];
    if (m != null) {
      m.text = newText;
      m.isEdited = true;
      m.textNotifier.value = newText;
    }
  }

  Future<void> _fetchHistory({bool loadMore = false, bool forceRefresh = false}) async {
    if (_myPhone == null) return;
    
    if (loadMore) {
      if (!_hasMore || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      // Only show main loader if we have no messages yet
      if (_messages.isEmpty) setState(() => _isLoading = true);
    }

    try {
      final result = await ChatRepository().getChatHistory(
        myPhone: _myPhone!,
        otherPhone: _normalizedReceiverPhone ?? widget.receiverPhone,
        page: loadMore ? _currentPage + 1 : 1,
        forceRefresh: forceRefresh,
      );

      final List<ChatMessage> fetched = result['messages'] ?? [];
      
          if (mounted) {
        setState(() {
          if (loadMore) {
            // Deduplicate when adding more
            for (var m in fetched) {
              if (_messageLookup[m.id] == null && _messageLookup[m.localId] == null) {
                _messages.add(m);
                _addToLookup(m);
              }
            }
            _currentPage++;
          } else {
            // Smart Refresh: Keep optimistic messages that aren't yet in the fetched list
            if (forceRefresh) {
              final optimisticOnes = _messages.where((m) => m.status == MessageStatus.sending || m.status == MessageStatus.error).toList();
              
              _messages.clear();
              _messageLookup.clear();

              // Add optimistic ones back first to maintain order (top of list)
              for (var m in optimisticOnes) {
                _messages.add(m);
                _addToLookup(m);
              }
              
              // Add fetched ones, but skip any that match an optimistic one by localId
              for (var m in fetched) {
                if (_messageLookup[m.id] == null && _messageLookup[m.localId] == null) {
                  _messages.add(m);
                  _addToLookup(m);
                }
              }
            } else if (fetched.isNotEmpty) {
              _messages.clear();
              _messageLookup.clear();
              for (var m in fetched) {
                _messages.add(m);
                _addToLookup(m);
              }
            }
            _isBlocked = result['isBlocked'] ?? false;
            _isPartnerDeactivated = result['isPartnerDeactivated'] ?? false;
            _hasReviewed = result['hasReviewed'] ?? false;
            _isLoading = false;
          }
          _hasMore = fetched.length >= 30;
          _isLoadingMore = false;
        });
      }

      // After loading history, mark all incoming as seen
      if (!loadMore && _messages.any((m) => !m.isMe && m.status != MessageStatus.seen)) {
        ChatRepository().markChatSeen(_myPhone!, _normalizedReceiverPhone ?? widget.receiverPhone);
      }
    } catch (e) {
      debugPrint("History fetch error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _sendMessage({String type = 'text', String? text, String? imageUrl, String? audioUrl, bool isViewOnce = false, String? customLocalId}) {
    if (_myPhone == null || _myName == null || _normalizedReceiverPhone == null) return;

    // Check message limit access
    if (!PremiumRepository().checkAccessAndShowOffer(context, feature: 'chat')) {
      return;
    }
    
    final String msgText = text ?? _messageController.text.trim();
    if (msgText.isEmpty && type == 'text') return;

    // Reset typing status immediately on send
    _isMeTyping = false;
    _typingTimer?.cancel();
    SocketService().emit('stop_typing', {'otherPhone': _normalizedReceiverPhone});

    final String localId = customLocalId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // 1. Send via Socket
    ChatRepository().sendMessage(
      senderPhone: _myPhone!,
      receiverPhone: _normalizedReceiverPhone!,
      senderName: _myName!,
      message: msgText,
      type: type,
      localId: localId,
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      isViewOnce: isViewOnce,
      replyToId: _replyingTo?.id,
      replyText: _replyingTo?.text,
      replyType: _replyingTo?.type,
      ack: (res) {
        if (res != null && res['success'] == true) {
          _updateMessageWithRealId(localId, res['messageId']);
          // NEW: Increment message count for trial limit
          PremiumService().incrementMessageCount();
        } else {
          // Show red error status if sending failed (e.g. blocked or server error)
          _updateMessageStatus(localId, MessageStatus.error);
        }
      }
    );

    // 2. Optimistic UI Update (Only if not already added by media uploader)
    if (customLocalId == null) {
      final optimisticMsg = ChatMessage(
        localId: localId,
        isMe: true,
        text: msgText,
        type: type,
        imageUrl: imageUrl,
        audioUrl: audioUrl,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        isViewOnce: isViewOnce,
        isNew: true, // Mark for animation
        replyToId: _replyingTo?.id,
        replyText: _replyingTo?.text,
        replyType: _replyingTo?.type,
      );

      _addToLookup(optimisticMsg);

      setState(() {
        _messageCount++;
        _adMessageCounter++;
        _messages.insert(0, optimisticMsg);
        _messageController.clear();
        _replyingTo = null;
      });
      _checkAndShowAdPopup();
      _checkAndShowReviewPopup();
      ChatRepository().updateCacheWithNewMessage(_myPhone!, widget.receiverPhone, optimisticMsg);
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      // For media, just clear input as it was already added optimistically
      setState(() {
        _messageCount++;
        _adMessageCounter++;
        _messageController.clear();
        _replyingTo = null;
      });
      _checkAndShowAdPopup();
      _checkAndShowReviewPopup();
    }
  }

  void _updateMessageWithRealId(String localId, String realId) {
    final m = _messageLookup[localId];
    if (m != null) {
      m.id = realId;
      _messageLookup[realId] = m;
      // Status should only move forward (handled by ChatMessage setter)
      m.status = MessageStatus.sent;
    }
  }

  void _checkAndShowAdPopup() {
    if (AdService().shouldShowAds && _adMessageCounter >= _targetAdCount) {
      // Don't show if ad is not ready to avoid frustration, or show only if we haven't shown recently
      _adMessageCounter = 0;
      _targetAdCount = AppConfigService().rewardMinMsg + Random().nextInt(AppConfigService().rewardMaxMsg - AppConfigService().rewardMinMsg + 1);
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showRewardAdPopup();
      });
    }
  }

  void _showRewardAdPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white10)),
        title: const Row(
          children: [
            Icon(Icons.card_giftcard_rounded, color: Colors.orangeAccent),
            SizedBox(width: 12),
            Text("Special Reward!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "Watch a short video to keep chatting for free or remove all ads forever.",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            children: [
              ElevatedButton(
                onPressed: () {
                  // Show loading indicator since Rewarded ads might take time
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loading Reward Ad...'), duration: Duration(seconds: 1))
                  );
                  
                  AdService().showRewardedAd(
                    onRewardEarned: (reward) {
                      Navigator.pop(context); // Close popup only after reward earned or ad closed
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reward Granted! Ads paused.')));
                    },
                    onAdClosed: () {
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    }
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("WATCH AD TO CONTINUE", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TrialOnboardingScreen(forceShow: true)));
                },
                child: const Text("REMOVE ADS & GO PREMIUM", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // UI Helpers
  void _handleTypingStatus() {
    if (_isPartnerDeactivated) return;

    if (_messageController.text.trim().isNotEmpty) {
      if (!_isMeTyping) {
        _isMeTyping = true;
        // Shadow Mode: We still emit typing so the server can ignore it silently
        SocketService().emit('typing', {'otherPhone': _normalizedReceiverPhone});
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(milliseconds: 1500), () {
        _isMeTyping = false;
        SocketService().emit('stop_typing', {'otherPhone': _normalizedReceiverPhone});
      });
    } else if (_isMeTyping) {
      _isMeTyping = false;
      _typingTimer?.cancel();
      SocketService().emit('stop_typing', {'otherPhone': _normalizedReceiverPhone});
    }
  }

  @override
  void dispose() {
    ModerationRepository().blockStatusNotifier.removeListener(_syncBlockFromGlobal);
    _typingTimer?.cancel();
    _micHoldTimer?.cancel();
    _messageController.removeListener(_handleTypingStatus);
    _scrollController.removeListener(_scrollListener);
    WidgetsBinding.instance.removeObserver(this);
    SocketService().leaveRoom();
    _socketSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    
    // Safety: Clear lookup and references immediately
    _messageLookup.clear();
    
    // We don't manually call m.dispose() here anymore because ValueListenableBuilders 
    // in the ListView might still be unmounting and need those notifiers for a few milliseconds.
    // Flutter's garbage collector will handle these as the list itself is cleared.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, // Keep this true for chat, but optimized elsewhere
      backgroundColor: const Color(0xFF121212),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
              : _buildMessageList(),
          ),
          if (_isPartnerDeactivated) _buildDeactivatedIndicator()
          else _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final displayName = _receiverName ?? widget.name;
    final displayDistance = _receiverDistance ?? widget.distance;
    final displayPosition = _receiverPosition ?? widget.position;

    return AppBar(
      backgroundColor: const Color(0xFF1C1421), // Baingani Black
      elevation: 0,
      leadingWidth: 40,
      title: InkWell(
        onTap: () => ProfileDetailPage.navigate(
          context, 
          phone: widget.receiverPhone, 
          name: displayName,
          distance: displayDistance,
          position: displayPosition,
          city: _receiverCity ?? "Unknown",
          area: _receiverArea ?? "Unknown",
          age: _receiverAge ?? 0,
          havePlace: _receiverHavePlace ?? "Unknown",
          isVerified: _isReceiverVerified ?? false,
          showMessageButton: false,
        ),
        child: Row(
          children: [
            Hero(
              tag: 'avatar_${widget.receiverPhone}',
              child: const CircleAvatar(radius: 18, backgroundColor: Colors.orangeAccent, child: Icon(Icons.person, color: Colors.black, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChatAppBarTitle(
                    name: displayName,
                    distance: displayDistance,
                    position: displayPosition,
                    phone: widget.receiverPhone,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam_rounded, color: Colors.orangeAccent),
          onPressed: () => _handleCall(true),
        ),
        IconButton(
          icon: const Icon(Icons.call_rounded, color: Colors.orangeAccent),
          onPressed: () => _handleCall(false),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSettingsPage(name: displayName, phone: widget.receiverPhone))),
        ),
      ],
    );
  }

  void _handleCall(bool isVideo) async {
    final displayName = _receiverName ?? widget.name;
    if (!PremiumRepository().checkAccessAndShowOffer(context, feature: 'call')) {
      return;
    }

    final hasPermission = await PermissionManager().checkAndRequestCallPermissions(context, isVideo: isVideo);
    if (hasPermission) {
      CallService().startCall(widget.receiverPhone, displayName, isVideo: isVideo);
    }
  }

  Widget _buildMessageList() {
    final bool showWarning = !_hasMore; // Show when reached the start of the chat history

    return RefreshIndicator(
      onRefresh: () => _fetchHistory(loadMore: true),
      color: Colors.orangeAccent,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
          cacheExtent: 1000,
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: _messages.length + 1 + (_isLoadingMore ? 1 : 0) + (showWarning ? 1 : 0),
          itemBuilder: (context, index) {
            // 1. Typing Indicator (Bottom)
            if (index == 0) {
              return ValueListenableBuilder<bool>(
                valueListenable: TypingManager().getTypingNotifier(_normalizedReceiverPhone),
                builder: (context, isTyping, _) {
                  // Optimization: Hide typing indicator if user is blocked
                  return AnimatedTypingIndicator(isTyping: !_isBlocked && isTyping);
                },
              );
            }

            // 2. Chat Messages
            final int msgIndex = index - 1;
            if (msgIndex < _messages.length) {
              final m = _messages[msgIndex];
              return PushAnimatedWidget(
                key: ValueKey(m.localId ?? m.id ?? m.timestamp.toString()),
                isNew: m.isNew,
                onComplete: () => m.isNew = false,
                child: ChatMessageTile(
                  message: m,
                  onLongPress: () => _showMessageOptions(m),
                  onViewOnceTap: () => _handleViewOnceMedia(m),
                  onImageTap: (url) => _openFullScreenMedia(url),
                  onVideoTap: (url) => _openVideoPlayer(url),
                ),
              );
            }

            // 3. Loading More Indicator (Oldest part of history)
            int currentPos = _messages.length;
            if (_isLoadingMore && msgIndex == currentPos) {
              return const Padding(
                padding: EdgeInsets.all(10),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)),
              );
            }
            if (_isLoadingMore) currentPos++;

            // 4. Safety Warning (Very Top of first chat session)
            if (showWarning && msgIndex == currentPos) {
              return _buildSafetyWarning();
            }

            return const SizedBox.shrink();
          },
        ),
    );
  }

  Widget _buildSafetyWarning() {
    // Get the timestamp of the very first message
    final DateTime startDate = _messages.isNotEmpty ? _messages.last.timestamp : DateTime.now();
    final String dateStr = DateFormat('EEE, MMM d').format(startDate);

    return Column(
      children: [
        // Date Header (Premium Pill)
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            dateStr,
            style: const TextStyle(
              color: Colors.white54, 
              fontSize: 11, 
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2
            ),
          ),
        ),
        
        // Safety Warning Box (Compact & Premium)
        Container(
          margin: const EdgeInsets.only(bottom: 30, left: 30, right: 30),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE082), // Back to original warm yellow
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("✅ ", style: TextStyle(fontSize: 12)), // Back to original emoji
                  Text(
                    'Keep your community safe',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'If any user asks for money, please report them immediately. We will remove them from the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: SafeArea(
        child: _isRecording 
          ? RecordingView(
              onCancel: () => _stopRecording(cancel: true),
              onStop: () => _stopRecording(cancel: false),
              isSlidingToCancelNotifier: _isSlidingToCancelNotifier,
              onActionIcon: _buildActionIcon(),
              durationNotifier: _recordDurationNotifier,
            )
          : _buildStandardInput(),
      ),
    );
  }

  Widget _buildStandardInput() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.orangeAccent, size: 28),
          onPressed: _showMediaOptions,
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingTo != null) _buildReplyingBar(),
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _buildActionIcon(),
      ],
    );
  }

  Widget _buildReplyingBar() {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Container(width: 4, height: 30, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Replying to", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(_replyingTo!.text ?? 'Media', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white24),
            onPressed: () => setState(() => _replyingTo = null),
          )
        ],
      ),
    );
  }

  Widget _buildActionIcon() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _messageController,
      builder: (context, value, _) {
        if (value.text.trim().isEmpty) {
          return Listener(
            onPointerDown: (_) {
              _micHoldTimer?.cancel();
              _micHoldTimer = Timer(const Duration(milliseconds: 300), () {
                _startRecording();
              });
            },
            onPointerUp: (_) {
              _micHoldTimer?.cancel();
              if (_isRecording) {
                _stopRecording();
              }
            },
            onPointerMove: (details) {
              if (!_isRecording) return;
              // Use global position or delta to detect slide
              if (details.localPosition.dx < -80) {
                if (!_isSlidingToCancelNotifier.value) {
                  _isSlidingToCancelNotifier.value = true;
                  HapticFeedback.lightImpact();
                }
              } else if (details.localPosition.dx > -20) {
                if (_isSlidingToCancelNotifier.value) {
                  _isSlidingToCancelNotifier.value = false;
                }
              }
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: _isSlidingToCancelNotifier,
              builder: (context, isSliding, _) {
                Color iconBgColor = Colors.orangeAccent;
                if (_isRecording) {
                  iconBgColor = isSliding ? Colors.redAccent : Colors.greenAccent;
                }

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.all(_isRecording ? 16 : 12),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                    boxShadow: _isRecording ? [
                      BoxShadow(
                        color: (isSliding ? Colors.red : Colors.green).withValues(alpha: 0.3),
                        blurRadius: 15, 
                        spreadRadius: 5
                      )
                    ] : [],
                  ),
                  child: Icon(
                    isSliding ? Icons.delete_outline_rounded : (_isRecording ? Icons.mic_rounded : Icons.mic_none_rounded),
                    color: Colors.black,
                    size: 24,
                  ),
                );
              }
            ),
          );
        }
        return IconButton(
          icon: const Icon(Icons.send_rounded, color: Colors.orangeAccent, size: 28),
          onPressed: () => _sendMessage(),
        );
      },
    );
  }

  // --- RECORDING LOGIC ---
  void _startRecording() async {
    if (!PremiumRepository().checkAccessAndShowOffer(context, feature: 'audio_msg')) {
      return;
    }
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) return;

    setState(() {
      _isRecording = true;
      _recordDurationNotifier.value = 0;
      _isSlidingToCancelNotifier.value = false;
      _isRecorderReady = false;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      _recordingPath = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.start(const RecordConfig(), path: _recordingPath!);
      
      if (mounted) {
        setState(() => _isRecorderReady = true);
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          _recordDurationNotifier.value++;
        });
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint("🚨 Error starting recording: $e");
      if (mounted) setState(() => _isRecording = false);
    }
  }

  void _stopRecording({bool cancel = false}) async {
    if (!_isRecording) return;
    
    // If user released too fast, wait for recorder to actually start
    if (!_isRecorderReady) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final bool shouldCancel = cancel || _isSlidingToCancelNotifier.value;
    _recordingTimer?.cancel();
    
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      debugPrint("🚨 Error stopping recorder: $e");
    }
    
    final int finalDuration = _recordDurationNotifier.value;
    final String? finalPath = path ?? _recordingPath;
    
    setState(() {
      _isRecording = false;
      _isRecorderReady = false;
    });
    _isSlidingToCancelNotifier.value = false;
    _recordDurationNotifier.value = 0;
    
    if (!shouldCancel && finalPath != null) {
      final file = File(finalPath);
      if (file.existsSync() && (finalDuration >= 1 || file.lengthSync() > 1000)) {
        _uploadAndSendMedia(file, 'audio');
      } else {
        debugPrint("⚠️ Recording too short or file empty");
      }
    } else if (shouldCancel) {
      HapticFeedback.vibrate();
    }
  }

  // --- MEDIA HANDLING ---
  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MediaSelectionModal(
        onMediaSelected: (file, type, isViewOnce, {existingUrl}) => 
            _uploadAndSendMedia(file, type, isViewOnce: isViewOnce, existingUrl: existingUrl),
      ),
    );
  }

  Future<void> _uploadAndSendMedia(File file, String type, {bool isViewOnce = false, String? existingUrl}) async {
    File fileToUpload = file;
    
    // 1. Show optimistic message immediately
    final String localId = 'media_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = ChatMessage(
      localId: localId,
      isMe: true,
      type: type,
      localFilePath: file.path,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      isViewOnce: isViewOnce,
      isNew: true,
    );
    
    _addToLookup(optimisticMsg);

    setState(() {
      _messages.insert(0, optimisticMsg);
    });
    ChatRepository().updateCacheWithNewMessage(_myPhone!, widget.receiverPhone, optimisticMsg);
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

    // 2. Perform compression in background (if needed)
    try {
      if (type == 'video' && existingUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Optimizing video for faster sending...'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blueAccent,
          ),
        );
        final compressed = await MediaService().compressVideo(file);
        if (compressed != null) {
          fileToUpload = compressed;
        }
      }

      String? remoteUrl = existingUrl;
      remoteUrl ??= await ChatRepository().uploadMedia(fileToUpload, _myPhone!, type);
      
      if (remoteUrl != null) {
        // Update optimistic message with remote URL
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.localId == localId);
            if (idx != -1) {
              if (type == 'audio') _messages[idx].audioUrl = remoteUrl;
              if (type == 'image' || type == 'video') _messages[idx].imageUrl = remoteUrl;
            }
          });
        }

        // 3. Send via Socket using the SAME localId
        _sendMessage(
          type: type,
          imageUrl: (type == 'image' || type == 'video') ? remoteUrl : null,
          audioUrl: type == 'audio' ? remoteUrl : null,
          isViewOnce: isViewOnce,
          customLocalId: localId,
        );
      } else {
        _updateMessageStatus(localId, MessageStatus.error);
      }
    } catch (e) {
      debugPrint("🚨 [UPLOAD_FAILED] $e");
      _updateMessageStatus(localId, MessageStatus.error);
    }
  }

  void _handleDeleteForMe(ChatMessage m) {
    if (m.id != null && _myPhone != null) {
      ChatRepository().deleteMessageForMe(m.id!, _myPhone!, widget.receiverPhone);
    }
    setState(() {
      _messages.remove(m);
      _messageLookup.remove(m.id);
      _messageLookup.remove(m.localId);
      m.dispose(); // Cleanup!
    });
  }

  void _handleViewOnceMedia(ChatMessage m) {
    if (m.isOpened) return;
    
    // Mark as opened immediately locally so UI updates right away
    final String? mediaUrl = m.imageUrl ?? m.audioUrl;
    if (mediaUrl == null) return;

    // Open Viewer first
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FullScreenMediaViewer(
        url: ApiService.getSecureUrl(mediaUrl), 
        isViewOnce: true,
        onDispose: () {
          // Final sync when closing
          if (mounted && !m.isOpened) {
            setState(() {
              m.isOpened = true;
              m.imageUrl = null;
              m.audioUrl = null;
            });
            ChatRepository().markOpened(m.id!, _myPhone!, widget.receiverPhone);
          }
        },
      ),
    )).then((_) {
      // Backup: Ensure status is updated when returning
      if (mounted && !m.isOpened) {
        setState(() {
          m.isOpened = true;
          m.imageUrl = null;
          m.audioUrl = null;
        });
        ChatRepository().markOpened(m.id!, _myPhone!, widget.receiverPhone);
      }
    });
  }

  void _openFullScreenMedia(String? url) {
    if (url == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FullScreenMediaViewer(url: ApiService.getSecureUrl(url)),
    ));
  }

  void _openVideoPlayer(String? url) {
    if (url == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FullScreenVideoPlayer(url: ApiService.getSecureUrl(url)),
    ));
  }

  void _showMessageOptions(ChatMessage m) {
    if (m.isDeletedForEveryone) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
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
                if (m.type != 'call_log')
                  ListTile(
                    leading: const Icon(Icons.reply_rounded, color: Colors.orangeAccent),
                    title: const Text('Reply', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _replyingTo = m);
                    },
                  ),
                if (m.type == 'text' && m.text != null)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: Colors.orangeAccent),
                    title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: m.text!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied to clipboard')));
                    },
                  ),
                if (m.isMe && m.id != null && m.type != 'call_log')
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(context);
                      ChatRepository().deleteMessageForEveryone(m.id!, _myPhone!, widget.receiverPhone);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                  title: const Text('Delete for Me', style: TextStyle(color: Colors.white38)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDeleteForMe(m);
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeactivatedIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.white.withValues(alpha: 0.05),
      child: const Text(
        'This account is no longer active',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white38),
      ),
    );
  }
}

class _ChatAppBarTitle extends StatelessWidget {
  final String name;
  final String distance;
  final String position;
  final String phone;

  const _ChatAppBarTitle({
    required this.name,
    required this.distance,
    required this.position,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        ValueListenableBuilder<bool>(
          valueListenable: PresenceManager().getStatusNotifier(phone, false),
          builder: (context, isOnline, _) {
            final String status = isOnline ? 'Online Now' : position;
            
            String dStr = "";
            final match = RegExp(r"(\d+(\.\d+)?)").firstMatch(distance);
            if (match != null) {
              double? dVal = double.tryParse(match.group(1)!);
              if (dVal != null && dVal < 0.5) dVal = 0.5;
              dStr = "${dVal?.toStringAsFixed(1) ?? match.group(1)} km";
            }

            return Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11),
                children: [
                  if (dStr.isNotEmpty) ...[
                    TextSpan(text: dStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    const TextSpan(text: ' • ', style: TextStyle(color: Colors.white54)),
                  ],
                  TextSpan(
                    text: status,
                    style: TextStyle(color: isOnline ? Colors.greenAccent : Colors.white54),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)));
  }
}

// --- HELPER COMPONENTS ---

class MediaSelectionModal extends StatefulWidget {
  final Function(File, String, bool, {String? existingUrl}) onMediaSelected;
  const MediaSelectionModal({super.key, required this.onMediaSelected});

  @override
  State<MediaSelectionModal> createState() => _MediaSelectionModalState();
}

class _MediaSelectionModalState extends State<MediaSelectionModal> {
  final ImagePicker _picker = ImagePicker();
  List<dynamic> _recentPhotos = [];
  bool _isLoadingPhotos = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _fetchRecentPhotos();
  }

  Future<void> _fetchRecentPhotos() async {
    final userData = await UserRepository().getCurrentUser();
    if (userData != null) {
      final photos = await ChatRepository().getRecentPhotos(userData['phone']);
      if (mounted) setState(() { _recentPhotos = photos; _isLoadingPhotos = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A), 
        borderRadius: BorderRadius.vertical(top: Radius.circular(32))
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, 
                height: 4, 
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildIconBtn(Icons.camera_alt_rounded, 'Camera', () => _pickMedia(ImageSource.camera)),
                  _buildIconBtn(Icons.videocam_rounded, 'Video', () => _pickMedia(ImageSource.camera, type: 'video')),
                  _buildIconBtn(Icons.image_rounded, 'Gallery', () => _pickMedia(ImageSource.gallery)),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 12),
                    const SizedBox(width: 6),
                    const Text('RECENT PHOTOS', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _isEditing = !_isEditing),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isEditing ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _isEditing ? Colors.orangeAccent : Colors.white10)
                        ),
                        child: Text(
                          _isEditing ? 'DONE' : 'EDIT', 
                          style: TextStyle(color: _isEditing ? Colors.orangeAccent : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: _isLoadingPhotos 
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
                  : (_recentPhotos.isEmpty 
                      ? const Center(child: Text('No recent photos', style: TextStyle(color: Colors.white10, fontSize: 12)))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _recentPhotos.length,
                          itemBuilder: (context, i) => _buildRecentPhotoItem(_recentPhotos[i]),
                        )),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentPhotoItem(dynamic photo) {
    final String photoUrl = photo['imageUrl'];
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _isEditing ? null : () async {
              final String? localPath = await _downloadToTemp(ApiService.getSecureUrl(photoUrl));
              if (localPath != null && mounted) {
                _navigateToPreview(File(localPath), 'image', existingUrl: photoUrl);
              }
            },
            child: Container(
              width: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16), 
                border: Border.all(color: Colors.white.withValues(alpha: 0.05))
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: ApiService.getSecureUrl(photoUrl), 
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
            ),
          ),
          if (_isEditing)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _deletePhoto(photo),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deletePhoto(dynamic photo) async {
    final String photoUrl = photo['imageUrl'];
    final userData = await UserRepository().getCurrentUser();
    if (userData != null) {
      final success = await ChatRepository().deleteRecentPhoto(userData['phone'], photoUrl);
      if (success && mounted) {
        setState(() {
          _recentPhotos.remove(photo);
          if (_recentPhotos.isEmpty) _isEditing = false;
        });
      }
    }
  }

  Future<String?> _downloadToTemp(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      final documentDirectory = await getTemporaryDirectory();
      final file = File('${documentDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.png');
      file.writeAsBytesSync(response.bodyBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Widget _buildIconBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.orangeAccent, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source, {String type = 'image'}) async {
    XFile? file;
    if (type == 'image') {
      file = await _picker.pickImage(
        source: source, 
        imageQuality: 60, // Compression
        maxWidth: 1200,
        maxHeight: 1200,
      );
    } else {
      file = await _picker.pickVideo(source: source);
    }

    if (file != null && mounted) {
      _navigateToPreview(File(file.path), type);
    }
  }

  void _navigateToPreview(File file, String type, {String? existingUrl}) async {
    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => MediaPreviewScreen(file: file, type: type))
    );
    
    if (result != null && result['file'] != null && mounted) {
      Navigator.pop(context);
      widget.onMediaSelected(
        result['file'], 
        type, 
        result['isViewOnce'] ?? false, 
        existingUrl: existingUrl
      );
    }
  }
}

class FullScreenMediaViewer extends StatefulWidget {
  final String url;
  final bool isViewOnce;
  final VoidCallback? onDispose;
  const FullScreenMediaViewer({super.key, required this.url, this.isViewOnce = false, this.onDispose});

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: !widget.isViewOnce,
        leading: widget.isViewOnce ? IconButton(
          icon: const Icon(Icons.close_rounded), 
          onPressed: () => Navigator.pop(context),
        ) : null,
      ),
      body: Center(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: widget.url))),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  const FullScreenVideoPlayer({super.key, required this.url});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint("🎬 [VIDEO_PLAYER] Initializing: ${widget.url}");
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        debugPrint("🎬 [VIDEO_PLAYER] Initialized Successfully");
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
        }
      }).catchError((e) {
        debugPrint("🚨 [VIDEO_PLAYER] Initialization Error: $e");
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    VideoProgressIndicator(_controller, allowScrubbing: true),
                    Center(
                      child: IconButton(
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                          color: Colors.white70,
                          size: 60,
                        ),
                        onPressed: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.orangeAccent),
      ),
    );
  }
}

class ChatMessageTile extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onLongPress;
  final VoidCallback onViewOnceTap;
  final Function(String?) onImageTap;
  final Function(String?) onVideoTap;

  const ChatMessageTile({
    super.key,
    required this.message,
    required this.onLongPress,
    required this.onViewOnceTap,
    required this.onImageTap,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.type == 'block_event' || m.type == 'unblock_event') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)),
          child: Text(m.text ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      );
    }

    return Align(
      alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: m.isDeletedForEveryone ? null : onLongPress,
        child: Column(
          crossAxisAlignment: m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (m.replyToId != null && !m.isDeletedForEveryone) _buildReplyPreview(m),
            if (m.isDeletedForEveryone) _buildDeletedMessage(context, m)
            else if (m.isViewOnce) _buildViewOnceBubble(context, m)
            else if (m.type == 'image' || m.type == 'video') _buildImageMessage(context, m)
            else if (m.type == 'audio') _buildAudioMessage(m)
            else if (m.type == 'call_log') _buildCallMessage(context, m)
            else _buildTextMessage(context, m),
            
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('hh:mm a').format(m.timestamp), style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  if (m.isMe) ...[
                    const SizedBox(width: 4),
                    ValueListenableBuilder<MessageStatus>(
                      valueListenable: m.statusNotifier,
                      builder: (context, status, _) => _buildStatusIcon(status),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedMessage(BuildContext context, ChatMessage m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block_rounded, size: 14, color: Colors.white24),
          const SizedBox(width: 8),
          Text(
            m.isMe ? "You deleted this message" : "This message was deleted",
            style: const TextStyle(color: Colors.white24, fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildViewOnceBubble(BuildContext context, ChatMessage m) {
    return ValueListenableBuilder<String>(
      valueListenable: PremiumService().statusNotifier,
      builder: (context, status, _) {
        final bool isPremium = status == "PREMIUM";
        final bool showLocked = !isPremium && !m.isMe;

        return ValueListenableBuilder<bool>(
          valueListenable: m.openedNotifier,
          builder: (context, isOpened, _) {
            if (isOpened) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all_rounded, size: 18, color: Colors.white24),
                    SizedBox(width: 10),
                    Text("Opened", style: TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }

            if (m.isMe) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.looks_one_rounded, size: 18, color: Colors.orangeAccent),
                    SizedBox(width: 10),
                    Text("1 Image", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            } else {
              if (showLocked) {
                return InkWell(
                  onTap: () => _showOfferPage(context),
                  child: Container(
                    width: 200,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _buildLockedMediaPlaceholder(m),
                    ),
                  ),
                );
              }
              // Receiver sees blurred image container
              return InkWell(
                onTap: onViewOnceTap,
                child: Container(
                  width: 200,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: ColorFiltered(
                            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.5), BlendMode.darken),
                            child: m.type == 'video' 
                              ? Container(color: Colors.black54)
                              : (m.imageUrl != null ? CachedNetworkImage(
                                  imageUrl: ApiService.getSecureUrl(m.imageUrl),
                                  fit: BoxFit.cover,
                                  memCacheWidth: 200,
                                ) : Container(color: Colors.black54)),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m.type == 'video' ? Icons.play_circle_outline_rounded : Icons.visibility_off_rounded, color: Colors.orangeAccent, size: 32),
                            const SizedBox(height: 8),
                            Text(m.type == 'video' ? "One View Video" : "One View Image", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            Text("Tap to view", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildReplyPreview(ChatMessage m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: Colors.orangeAccent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Replying to", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(m.replyText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTextMessage(BuildContext context, ChatMessage m) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      constraints: BoxConstraints(maxWidth: screenWidth * 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: m.isMe ? Colors.orangeAccent : const Color(0xFF262626),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(m.isMe ? 20 : 4),
          bottomRight: Radius.circular(m.isMe ? 4 : 20),
        ),
      ),
      child: ValueListenableBuilder<String?>(
        valueListenable: m.textNotifier,
        builder: (context, text, _) {
          return Text(
            text ?? '',
            style: TextStyle(
              color: m.isMe ? Colors.black : Colors.white,
              fontSize: 15,
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageMessage(BuildContext context, ChatMessage m) {
    final bool isVideo = m.type == 'video';
    
    return ValueListenableBuilder<String>(
      valueListenable: PremiumService().statusNotifier,
      builder: (context, status, _) {
        final bool isPremium = status == "PREMIUM";
        final bool showLocked = !isPremium && !m.isMe;

        return InkWell(
          onTap: () {
            if (showLocked) {
              _showOfferPage(context);
              return;
            }
            if (m.isViewOnce && !m.isMe && !m.isOpened) {
              onViewOnceTap();
            } else if (isVideo) {
              onVideoTap(m.imageUrl);
            } else {
              onImageTap(m.imageUrl);
            }
          },
          child: Container(
            width: 220,
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: showLocked 
                ? _buildLockedMediaPlaceholder(m)
                : (m.isViewOnce && !m.isMe && !m.isOpened 
                    ? _buildViewOncePlaceholder(m)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isVideo)
                            Container(
                              color: Colors.black54,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (m.localFilePath != null)
                                     Opacity(opacity: 0.3, child: Image.file(File(m.localFilePath!), fit: BoxFit.cover)),
                                  const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_circle_fill_rounded, color: Colors.orangeAccent, size: 50),
                                        SizedBox(height: 8),
                                        Text("Video Message", style: TextStyle(color: Colors.white54, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (m.localFilePath != null)
                            Image.file(File(m.localFilePath!), fit: BoxFit.cover, cacheWidth: 440)
                          else
                            CachedNetworkImage(
                              imageUrl: ApiService.getSecureUrl(m.imageUrl),
                              fit: BoxFit.cover,
                              memCacheWidth: 440,
                              placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white24),
                            ),
                        ],
                      )),
            ),
          ),
        );
      }
    );
  }

  Widget _buildLockedMediaPlaceholder(ChatMessage m) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (m.imageUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: CachedNetworkImage(
              imageUrl: ApiService.getSecureUrl(m.imageUrl),
              fit: BoxFit.cover,
            ),
          ),
        Container(color: Colors.black.withValues(alpha: 0.5)),
        const Positioned(
          top: 12,
          right: 12,
          child: Icon(Icons.lock_rounded, color: Colors.orangeAccent, size: 18),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.orangeAccent, size: 24),
              ),
              const SizedBox(height: 12),
              const Text("Unlock Media", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              Text("Premium Only", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  void _showOfferPage(BuildContext context) {
    // We will navigate directly to the OfferTrialScreen
    OfferTrialScreen.show(context);
  }

  Widget _buildViewOncePlaceholder(ChatMessage m) {
    final bool isVideo = m.type == 'video';
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isVideo ? Icons.play_circle_outline_rounded : Icons.visibility_off_rounded, color: Colors.orangeAccent, size: 40),
          const SizedBox(height: 8),
          Text(isVideo ? "View Once Video" : "View Once Photo", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const Text("Tap to view", style: TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildAudioMessage(ChatMessage m) {
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: m.isMe ? Colors.orangeAccent : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(m.isMe ? 20 : 4),
          bottomRight: Radius.circular(m.isMe ? 4 : 20),
        ),
      ),
      child: m.audioUrl != null || m.localFilePath != null
          ? AudioPlayerWidget(url: m.audioUrl ?? m.localFilePath!, isMe: m.isMe)
          : const Padding(
              padding: EdgeInsets.all(12),
              child: Text("Audio not available", style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
    );
  }

  Widget _buildCallMessage(BuildContext context, ChatMessage m) {
    final metadata = m.metadata ?? {};
    final String callType = metadata['callType'] ?? 'audio';
    final String status = metadata['status'] ?? 'missed';
    final int duration = (metadata['duration'] as num?)?.toInt() ?? 0;
    final bool isVideo = callType == 'video';

    IconData icon;
    String label;
    Color contentColor = m.isMe ? Colors.black : Colors.white;

    if (status == 'missed' || status == 'no_answer') {
      icon = isVideo ? Icons.missed_video_call_rounded : Icons.call_missed_rounded;
      label = m.isMe ? (status == 'no_answer' ? "No Answer" : "Cancelled") : "Missed Call";
      if (!m.isMe) contentColor = Colors.redAccent;
    } else if (status == 'rejected') {
      icon = isVideo ? Icons.videocam_off_rounded : Icons.call_end_rounded;
      label = "Declined";
    } else {
      icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
      label = isVideo ? "Video Call" : "Voice Call";
      if (duration > 0) {
        label += " (${_formatDuration(duration)})";
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: m.isMe ? Colors.orangeAccent : const Color(0xFF262626),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(m.isMe ? 20 : 4),
          bottomRight: Radius.circular(m.isMe ? 4 : 20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: contentColor),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: contentColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return "${seconds}s";
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    if (remainingSeconds == 0) return "${minutes}m";
    return "${minutes}m ${remainingSeconds}s";
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time_rounded, size: 12, color: Colors.white24);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 12, color: Colors.white24);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded, size: 12, color: Colors.white24);
      case MessageStatus.seen:
        return const Icon(Icons.done_all_rounded, size: 12, color: Colors.greenAccent);
      case MessageStatus.error:
        return const Icon(Icons.error_outline_rounded, size: 12, color: Colors.redAccent);
    }
  }
}

class RecordingView extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onStop;
  final ValueNotifier<bool> isSlidingToCancelNotifier;
  final Widget onActionIcon;
  final ValueNotifier<int> durationNotifier;

  const RecordingView({
    super.key,
    required this.onCancel,
    required this.onStop,
    required this.isSlidingToCancelNotifier,
    required this.onActionIcon,
    required this.durationNotifier,
  });

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 12),
          _PulsingDot(),
          const SizedBox(width: 12),
          ValueListenableBuilder<int>(
            valueListenable: durationNotifier,
            builder: (context, seconds, _) {
              return Text(
                _formatDuration(seconds),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              );
            },
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: isSlidingToCancelNotifier,
                builder: (context, isSliding, _) {
                  return Opacity(
                    opacity: isSliding ? 1.0 : 0.3,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left_rounded, size: 18, color: isSliding ? Colors.redAccent : Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          isSliding ? "RELEASE TO CANCEL" : "Slide to cancel",
                          style: TextStyle(
                            color: isSliding ? Colors.redAccent : Colors.white, 
                            fontSize: 12, 
                            fontWeight: isSliding ? FontWeight.bold : FontWeight.normal
                          ),
                        ),
                      ],
                    ),
                  );
                }
              ),
            ),
          ),
          onActionIcon,
        ],
      ),
    );
  }
}
