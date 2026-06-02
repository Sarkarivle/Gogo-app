import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/home/screens/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Page 1 Data
  final TextEditingController _nicknameController = TextEditingController();
  final FocusNode _nicknameFocusNode = FocusNode();
  String? _selectedDay;
  String? _selectedMonth;
  String? _selectedYear;
  String? _havePlace = 'NO'; // Default set to NO as requested

  // Page 2 Data
  String? _selectedPosition = 'Top'; // Default set to Top as requested

  bool _isLoading = false;

  final List<String> _days = List.generate(31, (index) => (index + 1).toString().padLeft(2, '0'));
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  final List<String> _years = List.generate(60, (index) => (DateTime.now().year - 18 - index).toString());

  @override
  void dispose() {
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showDayPicker() {
    _showPicker('Select Day', _days, (value) {
      setState(() => _selectedDay = value);
      Navigator.pop(context);
      Future.delayed(const Duration(milliseconds: 300), _showMonthPicker);
    });
  }

  void _showMonthPicker() {
    _showPicker('Select Month', _months, (value) {
      setState(() => _selectedMonth = value);
      Navigator.pop(context);
      Future.delayed(const Duration(milliseconds: 300), _showYearPicker);
    });
  }

  void _showYearPicker() {
    _showPicker('Select Year', _years, (value) {
      setState(() => _selectedYear = value);
      Navigator.pop(context);
    });
  }

  void _showPicker(String title, List<String> items, Function(String) onSelect) {
    _nicknameFocusNode.unfocus(); // Forcefully remove focus from Nickname
    FocusScope.of(context).requestFocus(FocusNode()); // Switch focus to a blank node

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) => ListTile(
                  title: Text(items[index], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  onTap: () => onSelect(items[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitData() async {
    if (_selectedPosition == null) return;

    setState(() => _isLoading = true);

    try {
      final userData = UserRepository().currentUser;
      if (userData == null) return;

      final response = await ApiService.post('/api/user/update-profile', {
        'phone': userData['phone'],
        'name': _nicknameController.text.trim(),
        'dobDay': _selectedDay,
        'dobMonth': _selectedMonth,
        'dobYear': _selectedYear,
        'havePlace': _havePlace,
        'position': _selectedPosition,
        'hasCompletedOnboarding': true,
      });

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await UserRepository().updateLocalUser(data['user']);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Error updating profile')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection error. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Progress Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: Container(height: 4, decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(width: 12),
                  Expanded(child: Container(height: 4, decoration: BoxDecoration(color: _currentPage == 1 ? Colors.orangeAccent : Colors.white24, borderRadius: BorderRadius.circular(2)))),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _currentPage == 0 ? 'Create Profile' : 'My Position',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildPageOne(),
                  _buildPageTwo(),
                ],
              ),
            ),
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPageOne() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nickname (not your original name)', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 12),
          TextField(
            controller: _nicknameController,
            focusNode: _nicknameFocusNode,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            onChanged: (v) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Nickname (not your original name)',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1)),
            ),
          ),
          const SizedBox(height: 35),
          const Text('Date of Birth', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildDateBox('Day', _selectedDay ?? 'DD', _showDayPicker)),
              const SizedBox(width: 12),
              Expanded(child: _buildDateBox('Month', _selectedMonth?.substring(0, 3).toUpperCase() ?? 'MM', _showMonthPicker)),
              const SizedBox(width: 12),
              Expanded(child: _buildDateBox('Year', _selectedYear ?? 'YYYY', _showYearPicker)),
            ],
          ),
          const SizedBox(height: 40),
          const Text('Do you have a place to meet?', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _buildOptionButton('YES', _havePlace == 'YES', () => setState(() => _havePlace = 'YES'))),
              const SizedBox(width: 16),
              Expanded(child: _buildOptionButton('NO', _havePlace == 'NO', () => setState(() => _havePlace = 'NO'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageTwo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildPositionCard('Top', 'Prefers leading role in intimacy', Icons.keyboard_double_arrow_up),
          const SizedBox(height: 12),
          _buildPositionCard('Bottom', 'Prefers receiving role in intimacy', Icons.keyboard_double_arrow_down),
          const SizedBox(height: 12),
          _buildPositionCard('Versatile', 'Comfortable in both roles', Icons.swap_vert),
          const SizedBox(height: 12),
          _buildPositionCard('Vers Top', 'Versatile but prefers being Top', Icons.vertical_align_top_rounded),
          const SizedBox(height: 12),
          _buildPositionCard('Vers Bottom', 'Versatile but prefers being Bottom', Icons.vertical_align_bottom_rounded),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDateBox(String label, String value, VoidCallback onTap) {
    bool isPlaceholder = value == 'DD' || value == 'MM' || value == 'YYYY';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: isPlaceholder ? Colors.transparent : Colors.orangeAccent.withValues(alpha: 0.4)),
            ),
            child: Text(value, style: TextStyle(color: isPlaceholder ? Colors.white24 : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton(String text, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus(); // Dismiss keyboard when selecting options
        onTap();
      },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.1) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white.withValues(alpha: 0.05)),
        ),
        child: Text(
          text,
          style: TextStyle(color: isSelected ? Colors.orangeAccent : Colors.white38, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPositionCard(String title, String description, IconData icon) {
    bool isSelected = _selectedPosition == title;
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus(); // Dismiss keyboard if any
        setState(() => _selectedPosition = title);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.08) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: -2)
          ] : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? Colors.orangeAccent : Colors.white38, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isSelected ? Colors.orangeAccent : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(color: isSelected ? Colors.white60 : Colors.white24, fontSize: 11)),
                ],
              ),
            ),
            if (isSelected) 
              const Icon(Icons.check_circle_rounded, color: Colors.orangeAccent, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    bool isFirstPage = _currentPage == 0;
    bool canGoNext = isFirstPage && 
        _nicknameController.text.trim().isNotEmpty && 
        _selectedDay != null && 
        _selectedMonth != null && 
        _selectedYear != null && 
        _havePlace != null;
    
    bool canSubmit = !isFirstPage && _selectedPosition != null;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: _isLoading 
              ? null 
              : (isFirstPage 
                  ? (canGoNext ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null)
                  : (canSubmit ? _submitData : null)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            disabledBackgroundColor: Colors.white10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 0,
          ),
          child: _isLoading 
              ? const CircularProgressIndicator(color: Colors.black)
              : Text(
                  isFirstPage ? 'Next' : 'Submit',
                  style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}
