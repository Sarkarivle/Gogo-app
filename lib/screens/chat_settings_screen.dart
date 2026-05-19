import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class ChatSettingsPage extends StatefulWidget {
  final String name;
  final String phone;

  const ChatSettingsPage({super.key, required this.name, required this.phone});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  bool _notificationsOn = true;
  bool _isActionInProgress = false;
  bool _isBlockedByMe = false;
  bool _amIBlocked = false;

  @override
  void initState() {
    super.initState();
    _checkBlockStatus();
  }

  Future<void> _checkBlockStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_data');
      if (userData == null) return;
      final myPhone = jsonDecode(userData)['phone'];
      
      // Check if I blocked them
      final res1 = await ApiService.get('/api/chat/check-block/$myPhone/${widget.phone}');
      final data1 = jsonDecode(res1.body);
      
      // Check if they blocked me
      final res2 = await ApiService.get('/api/chat/check-block/${widget.phone}/$myPhone');
      final data2 = jsonDecode(res2.body);

      if (mounted) {
        setState(() {
          _isBlockedByMe = data1['isBlocked'] ?? false;
          _amIBlocked = data2['isBlocked'] ?? false;
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(withReport ? Icons.report_gmailerrorred_rounded : Icons.block_flipped, color: Colors.red, size: 22),
                ),
                const SizedBox(width: 15),
                Text(withReport ? 'Report & Block User' : 'User ko block kare', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
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
                const SizedBox(height: 20),
                TextField(
                  controller: otherReasonController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Detail mein batalen',
                    hintStyle: const TextStyle(color: Colors.white10),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.white10)),
                  ),
                ),
              ],
              
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: selectedCategory == null ? null : () => _submitAction(selectedCategory!, otherReasonController.text, withReport),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: const Text('Submit', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              const SizedBox(height: 40),
            ],
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
      final prefs = await SharedPreferences.getInstance();
      final myPhone = jsonDecode(prefs.getString('user_data') ?? '{}')['phone'];

      await ApiService.post('/api/chat/block', {
        'blockerPhone': myPhone,
        'blockedPhone': widget.phone,
        'reason': reason,
        'isReported': withReport
      });

      if (withReport) {
        await ApiService.post('/api/user/report', {
          'reporterPhone': myPhone,
          'reportedPhone': widget.phone,
          'category': reason,
          'reportType': 'Report & Block',
          'description': details,
        });
      }

      // Notify server via socket for real-time sync
      SocketService().emit('notify_block', {
        'blockerPhone': myPhone,
        'blockedPhone': widget.phone,
      });

      if (mounted) {
        setState(() => _isBlockedByMe = true);
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed')));
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Color(0xFFFFC107), size: 60),
              const SizedBox(height: 24),
              const Text('User blocked', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('This user will no longer be able to message you.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context, true); // Close Settings and signal refresh
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))),
                child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUnblock() async {
    final prefs = await SharedPreferences.getInstance();
    final myPhone = jsonDecode(prefs.getString('user_data') ?? '{}')['phone'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Unblock User?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isActionInProgress = true);
              try {
                await ApiService.post('/api/chat/unblock', {
                  'blockerPhone': myPhone,
                  'blockedPhone': widget.phone,
                });
                
                // Notify server via socket
                SocketService().emit('notify_unblock', {
                  'blockerPhone': myPhone,
                  'blockedPhone': widget.phone,
                });

                if (mounted) {
                  setState(() => _isBlockedByMe = false);
                  Navigator.pop(context, true); // Redirect back to chat with refresh signal
                }
              } catch (e) {
                debugPrint('Unblock error: $e');
              } finally {
                if (mounted) setState(() => _isActionInProgress = false);
              }
            }, 
            child: const Text('UNBLOCK', style: TextStyle(color: Colors.orangeAccent))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17),
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
                    Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildSettingTile(Icons.notifications_none_rounded, 'Notifications', 
                trailing: Text(_notificationsOn ? 'On' : 'Off', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                onTap: () => setState(() => _notificationsOn = !_notificationsOn)
              ),
              
              if (_amIBlocked)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('You are blocked by this user', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                )
              else if (!_isBlockedByMe) ...[
                _buildSettingTile(Icons.star_border_rounded, 'Save as Favourites', onTap: () {}),
                _buildSettingTile(Icons.block_flipped, 'Block', color: Colors.redAccent, onTap: () => _showBlockUI(withReport: false)),
                _buildSettingTile(Icons.report_gmailerrorred_rounded, 'Report & Block', color: Colors.redAccent, isLast: true, onTap: () => _showBlockUI(withReport: true)),
              ] else ...[
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
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isLast ? Colors.transparent : Colors.white.withOpacity(0.05)))),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color ?? Colors.orangeAccent, size: 24),
        title: Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white12, size: 20),
      ),
    );
  }
}
