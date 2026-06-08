import 'dart:async';
import 'package:flutter/material.dart';

import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/profile/repositories/moderation_repository.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class ChatSettingsPage extends StatefulWidget {
  final String name;
  final String phone;

  const ChatSettingsPage({super.key, required this.name, required this.phone});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  bool _notificationsOn = true;
  bool _isFavourite = false;
  bool _isActionInProgress = false;
  bool _isBlockedByMe = false;
  bool _amIBlocked = false;

  StreamSubscription? _socketEventSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _listenToSocket();
  }

  Future<void> _loadSettings() async {
    setState(() => _isActionInProgress = true);
    await Future.wait([
      _checkBlockStatus(),
      _fetchMetadata(),
    ]);
    if (mounted) setState(() => _isActionInProgress = false);
  }

  Future<void> _fetchMetadata() async {
    try {
      final user = UserRepository().currentUser;
      if (user == null) return;
      
      // Using existing history call which already includes meta on the server side
      final history = await ChatRepository().getChatHistory(
        myPhone: user['phone'], 
        otherPhone: widget.phone,
        limit: 1
      );
      
      if (mounted) {
        setState(() {
          _isFavourite = history['isFavourite'] ?? false;
          _notificationsOn = !(history['isMuted'] ?? false);
        });
      }
    } catch (e) {
      debugPrint('Metadata error: $e');
    }
  }

  void _listenToSocket() {
    _socketEventSub = SocketService().eventStream.listen((event) {
      if (!mounted) return;
      if (event['event'] == 'moderation_state_updated') {
        final data = event['data'];
        final user = UserRepository().currentUser;
        if (user != null) {
          final String? myPhone = PhoneUtils.normalize(user['phone']);
          final String? otherPhone = PhoneUtils.normalize(widget.phone);
          
          final String? eventBlocker = PhoneUtils.normalize(data['blockerPhone']?.toString());
          final String? eventBlocked = PhoneUtils.normalize(data['blockedPhone']?.toString());

          if (eventBlocker == null || eventBlocked == null) return;

          // Check if this event involves both users in this chat
          final bool isMatch = (eventBlocker == myPhone && eventBlocked == otherPhone) ||
                               (eventBlocker == otherPhone && eventBlocked == myPhone);

          if (isMatch) {
            setState(() {
              _isBlockedByMe = (data['isBlocked'] == true) && (eventBlocker == myPhone);
              _amIBlocked = (data['isBlocked'] == true) && (eventBlocker == otherPhone);
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _socketEventSub?.cancel();
    super.dispose();
  }

  Future<void> _checkBlockStatus() async {
    try {
      final user = UserRepository().currentUser;
      if (user == null) return;
      final myPhone = user['phone'];
      
      final data = await ModerationRepository().checkBlockStatus(myPhone, widget.phone);
      
      if (mounted) {
        setState(() {
          _isBlockedByMe = (data['isBlocked'] ?? false) && data['blockerPhone'] == myPhone;
          _amIBlocked = (data['isBlocked'] ?? false) && data['blockerPhone'] == widget.phone;
        });
      }
    } catch (e) {
      debugPrint('Check block error: $e');
    }
  }

  void _showBlockUI({bool withReport = false}) {
    if (_amIBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot perform this action')));
      return;
    }

    String? selectedCategory;
    final otherReasonController = TextEditingController();
    bool isOtherSelected = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: StatefulBuilder(
                      builder: (context, setModalState) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Icon(withReport ? Icons.report_gmailerrorred_rounded : Icons.block_flipped, color: Colors.red, size: 22),
                            ),
                            const SizedBox(width: 15),
                            Text(withReport ? 'Report & Block User' : 'User ko block kare', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          ]),
                          const SizedBox(height: 12),
                          Text('Aap is profile ko kyun ${withReport ? 'report aur ' : ''}block kar rahe hain?', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 24),
                          
                          _buildModernOption('User galat behavior kar raha hai', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildModernOption('User paise maang raha hai', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildModernOption('Main ab unse baat nahi karna chahta', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = false; });
                          }),
                          _buildModernOption('Koi aur reason hai', selectedCategory, (val) {
                            setModalState(() { selectedCategory = val; isOtherSelected = true; });
                          }),

                          if (isOtherSelected) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: otherReasonController,
                              maxLines: 2,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Detail mein batalen',
                                hintStyle: const TextStyle(color: Colors.white10),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.03),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: selectedCategory == null ? null : () => _submitAction(selectedCategory!, otherReasonController.text, withReport),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC107),
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernOption(String title, String? selected, Function(String) onTap) {
    bool isSelected = selected == title;
    return InkWell(
      onTap: () => onTap(title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white12, width: 2),
                borderRadius: BorderRadius.circular(6),
                color: isSelected ? Colors.orangeAccent : Colors.transparent,
              ),
              child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
            ),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAction(String reason, String details, bool withReport) async {
    Navigator.pop(context);
    setState(() => _isActionInProgress = true);
    
    try {
      final user = UserRepository().currentUser;
      final myPhone = user?['phone'];
      if (myPhone == null) return;

      // Realtime Block via dedicated repository
      ModerationRepository().blockUser(
        blockerPhone: myPhone,
        blockedPhone: widget.phone,
        reason: reason,
      );

      if (withReport) {
        await ModerationRepository().reportUser(
          reporterPhone: myPhone,
          reportedPhone: widget.phone,
          category: reason,
          reportType: 'Report & Block',
          description: details,
        );
      }

      if (mounted) {
        // Local state update will also be reinforced by socket listener
        setState(() => _isBlockedByMe = true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed')));
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _handleUnblock() async {
    final user = UserRepository().currentUser;
    final myPhone = user?['phone'];
    if (myPhone == null) return;

    setState(() => _isActionInProgress = true);
    try {
      // Realtime Unblock via repository
      ModerationRepository().unblockUser(
        blockerPhone: myPhone, 
        blockedPhone: widget.phone
      );

      if (mounted) {
        setState(() => _isBlockedByMe = false);
      }
    } catch (e) {
      debugPrint('Unblock error: $e');
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _toggleMute() async {
    final user = UserRepository().currentUser;
    if (user == null) return;

    final newVal = !_notificationsOn;
    setState(() => _notificationsOn = newVal);
    
    await ChatRepository().updateConversationMetadata(
      myPhone: user['phone'], 
      otherPhone: widget.phone,
      isMuted: !newVal
    );
  }

  Future<void> _toggleFavourite() async {
    final user = UserRepository().currentUser;
    if (user == null) return;

    final newVal = !_isFavourite;
    setState(() => _isFavourite = newVal);
    
    await ChatRepository().updateConversationMetadata(
      myPhone: user['phone'], 
      otherPhone: widget.phone,
      isFavourite: newVal
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1421), // Baingani Black
        elevation: 0,
        title: const Text('Chat Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 30),
              Center(
                child: Column(
                  children: [
                    const CircleAvatar(radius: 45, backgroundColor: Colors.white10, child: Icon(Icons.person, size: 50, color: Colors.white54)),
                    const SizedBox(height: 16),
                    Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildSettingTile(
                _notificationsOn ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, 
                'Notifications', 
                trailing: Switch(
                  value: _notificationsOn, 
                  activeTrackColor: Colors.orangeAccent.withValues(alpha: 0.5),
                  activeThumbColor: Colors.orangeAccent,
                  onChanged: (v) => _toggleMute(),
                ),
                onTap: _toggleMute
              ),
              _buildSettingTile(
                _isFavourite ? Icons.star_rounded : Icons.star_border_rounded, 
                'Save as Favourites', 
                color: _isFavourite ? Colors.orangeAccent : null,
                onTap: _toggleFavourite
              ),
              
              if (_amIBlocked)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'You are blocked by this user', 
                      style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              
              if (!_isBlockedByMe && !_amIBlocked) ...[
                _buildSettingTile(Icons.block_flipped, 'Block', color: Colors.redAccent, onTap: () => _showBlockUI(withReport: false)),
                _buildSettingTile(Icons.report_gmailerrorred_rounded, 'Report & Block', color: Colors.redAccent, isLast: true, onTap: () => _showBlockUI(withReport: true)),
              ] else if (_isBlockedByMe) ...[
                _buildSettingTile(Icons.lock_open_rounded, 'Unblock', color: Colors.greenAccent, isLast: true, onTap: _handleUnblock),
              ],
            ],
          ),
          if (_isActionInProgress) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))),
        ],
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, {Color? color, Widget? trailing, bool isLast = false, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isLast ? Colors.transparent : Colors.white.withValues(alpha: 0.05)))),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color ?? Colors.orangeAccent, size: 24),
        title: Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white12, size: 20),
      ),
    );
  }
}
