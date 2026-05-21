import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/premium_service.dart';
import 'chat_screen.dart';
import 'onboarding/payment_screen.dart';

class ProfileDetailPage extends StatefulWidget {
  final String name;
  final String phone;
  final String distance;
  final String city;
  final String area;
  final int age;
  final String position;
  final String havePlace;
  final bool showMessageButton;
  final bool isVerified;
  final bool isOnline;

  const ProfileDetailPage({
    super.key,
    required this.name,
    required this.phone,
    required this.distance,
    required this.city,
    required this.area,
    required this.age,
    required this.position,
    required this.havePlace,
    this.showMessageButton = true,
    this.isVerified = false,
    this.isOnline = false,
  });

  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  void _showReportDialog() {
    String? selectedCategory;
    final otherReasonController = TextEditingController();
    bool isOtherSelected = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('User ko report kare', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ]),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Aap is profile ko kyun report kar rahe hain?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('Aapki report kisi pta nhi chalegi.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 20),
              
              _buildReportOption('User galat behavior kar raha hai', selectedCategory, (val) {
                setModalState(() { selectedCategory = val; isOtherSelected = false; });
              }),
              _buildReportOption('User paise maang raha hai', selectedCategory, (val) {
                setModalState(() { selectedCategory = val; isOtherSelected = false; });
              }),
              _buildReportOption('User fake photos share kar raha hai', selectedCategory, (val) {
                setModalState(() { selectedCategory = val; isOtherSelected = false; });
              }),
              _buildReportOption('Koi aur reason hai', selectedCategory, (val) {
                setModalState(() { selectedCategory = val; isOtherSelected = true; });
              }),

              if (isOtherSelected) ...[
                const SizedBox(height: 20),
                const Text('Apni problem likho', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: otherReasonController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Detail mein batalen',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
              ],
              
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: selectedCategory == null ? null : () => _submitReport(selectedCategory!, otherReasonController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: const Text('Submit', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportOption(String title, String? selected, Function(String) onTap) {
    bool isSelected = selected == title;
    return InkWell(
      onTap: () => onTap(title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: isSelected ? Colors.orangeAccent : Colors.white24),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(String category, String detail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myData = jsonDecode(prefs.getString('user_data') ?? '{}');
      final myPhone = myData['phone'];

      final response = await ApiService.post('/api/user/report', {
        'reporterPhone': myPhone,
        'reportedPhone': widget.phone,
        'category': category,
        'description': detail,
      });

      if (mounted) {
        Navigator.pop(context); // Close sheet
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted successfully')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit report')));
    }
  }

  @override
  Widget build(BuildContext context) {
    String locName = "";
    if (widget.area != null && widget.area.isNotEmpty && widget.area != "Unknown") {
      locName = widget.area;
    } else if (widget.city != null && widget.city.isNotEmpty && widget.city != "Unknown") {
      locName = widget.city;
    }

    String locationDisplay = locName.isNotEmpty ? "$locName, ${widget.distance}" : widget.distance;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 180,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF2A0D17),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: _showReportDialog,
                  )
                ],
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                  child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.orange.withOpacity(0.1), Colors.purple.withOpacity(0.1), const Color(0xFF0F0F0F)],
                          ),
                        ),
                      ),
                      Center(child: Icon(Icons.person_rounded, size: 80, color: Colors.white.withOpacity(0.1))),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(widget.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
                              if (widget.isVerified) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.verified, color: Colors.blueAccent, size: 28),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.location_on_rounded, color: Colors.orangeAccent, size: 18),
                              const SizedBox(width: 6),
                              Text(locationDisplay, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
                            ]),
                          ]),
                          ValueListenableBuilder<Map<String, bool>>(
                            valueListenable: SocketService().onlineUsers,
                            builder: (context, onlineMap, _) {
                              final bool isOnline = onlineMap[widget.phone] ?? widget.isOnline;
                              if (!isOnline) return const SizedBox.shrink();
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withOpacity(0.3))),
                                child: const Row(children: [CircleAvatar(backgroundColor: Colors.greenAccent, radius: 4), SizedBox(width: 8), Text('Online', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
                              );
                            }
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Row(children: [
                        _buildDetailChip(Icons.calendar_today_rounded, '${widget.age}', 'Age'),
                        const SizedBox(width: 12),
                        _buildDetailChip(Icons.straighten_rounded, widget.position, 'Position'),
                        const SizedBox(width: 12),
                        _buildDetailChip(Icons.home_rounded, widget.havePlace, 'Place'),
                      ]),
                      const SizedBox(height: 40),
                      const Text('About Me', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 12),
                      Text('Hey! मैं ${widget.name} हूँ। मैं किसी ऐसे इंसान की तलाश में हूँ जिससे मैं कनेक्ट हो सकूँ और साथ में ${widget.city.isNotEmpty ? widget.city : 'शहर'} घूम सकूँ।', style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6), height: 1.5)),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (widget.showMessageButton)
            Positioned(
              bottom: 50,
              left: 24,
              right: 24,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () async {
                      final isPremium = await PremiumService().checkPremiumAndRedirect(context);
                      if (!isPremium) return;

                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatPage(
                            name: widget.name,
                            receiverPhone: widget.phone,
                            distance: widget.distance,
                            position: widget.position,
                          ),
                        ),
                      );
                    },
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_rounded, color: Colors.black, size: 24),
                          const SizedBox(width: 12),
                          Text('Send Message', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.1))),
        child: Column(children: [
          Icon(icon, color: Colors.orangeAccent, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
        ]),
      ),
    );
  }
}
