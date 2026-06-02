import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _dayController = TextEditingController();
  final _monthController = TextEditingController();
  final _yearController = TextEditingController();
  final _bioController = TextEditingController();
  final _weightController = TextEditingController();
  
  String _selectedPosition = 'Top';
  String _havePlace = 'YES';
  String _selectedHeightFt = '5';
  String _selectedHeightInch = '7';
  bool _isLoading = false;
  Map<String, dynamic>? currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      currentUser = jsonDecode(userDataStr);
      setState(() {
        _nameController.text = currentUser!['name'] ?? '';
        _dayController.text = currentUser!['dobDay'] ?? '';
        _monthController.text = currentUser!['dobMonth'] ?? '';
        _yearController.text = currentUser!['dobYear'] ?? '';
        _bioController.text = currentUser!['bio'] ?? '';
        _weightController.text = currentUser!['weight'] ?? '';
        String dbPos = currentUser!['position'] ?? 'Top';
        List<String> validPositions = ['Top', 'Bottom', 'Versatile', 'Top, Ver'];
        _selectedPosition = validPositions.contains(dbPos) ? dbPos : 'Top';
        _havePlace = currentUser!['havePlace'] ?? 'YES';
        _selectedHeightFt = currentUser!['heightFt'] ?? '5';
        _selectedHeightInch = currentUser!['heightInch'] ?? '7';
      });
    }
  }

  Future<void> _saveProfile() async {
    // Bio is now optional, so no length check needed here unless it's not empty
    if (_bioController.text.isNotEmpty && _bioController.text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bio if provided must be at least 5 characters')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updateData = {
        'phone': currentUser!['phone'],
        'name': _nameController.text.trim(),
        'dobDay': _dayController.text.trim(),
        'dobMonth': _monthController.text.trim(),
        'dobYear': _yearController.text.trim(),
        'position': _selectedPosition,
        'havePlace': _havePlace,
        'bio': _bioController.text.trim(),
        'heightFt': _selectedHeightFt,
        'heightInch': _selectedHeightInch,
        'weight': _weightController.text.trim(),
      };
      final response = await ApiService.post('/api/user/update-profile', updateData);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final prefs = await SharedPreferences.getInstance();
          
          Map<String, dynamic> existingData = jsonDecode(prefs.getString('user_data') ?? '{}');
          Map<String, dynamic> newData = Map<String, dynamic>.from(data['user']);
          existingData.addAll(newData);
          
          await UserRepository().updateLocalUser(existingData);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
            );
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17),
        elevation: 0,
        centerTitle: true,
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('BASIC INFORMATION'),
            _buildLabel('Nickname (Public Name)'),
            _buildTextField(_nameController, 'Enter your name', icon: Icons.person_outline),
            
            const SizedBox(height: 24),
            _buildLabel('Date of Birth'),
            Row(
              children: [
                Expanded(child: _buildDOBField(_dayController, 'DD')),
                const SizedBox(width: 12),
                Expanded(child: _buildDOBField(_monthController, 'MM')),
                const SizedBox(width: 12),
                Expanded(child: _buildDOBField(_yearController, 'YYYY')),
              ],
            ),
            
            const SizedBox(height: 32),
            _buildSectionTitle('PREFERENCES'),
            _buildLabel('Your Position'),
            _buildDropdown(['Top', 'Bottom', 'Versatile', 'Top, Ver'], _selectedPosition, (v) => setState(() => _selectedPosition = v!)),
            
            const SizedBox(height: 24),
            _buildLabel('Do you have a place to meet?'),
            Row(
              children: [
                Expanded(child: _buildToggleButton('YES', _havePlace == 'YES', () => setState(() => _havePlace = 'YES'))),
                const SizedBox(width: 12),
                Expanded(child: _buildToggleButton('NO', _havePlace == 'NO', () => setState(() => _havePlace = 'NO'))),
              ],
            ),
            
            const SizedBox(height: 32),
            _buildSectionTitle('ABOUT ME (OPTIONAL)'),
            _buildLabel('Bio'),
            _buildTextField(_bioController, 'Write a little about yourself...', maxLines: 4),
            
            const SizedBox(height: 32),
            _buildSectionTitle('PHYSICAL DETAILS'),
            _buildLabel('Height'),
            Row(
              children: [
                Expanded(child: _buildDropdown(List.generate(4, (i)=>(i+4).toString()), _selectedHeightFt, (v)=>setState(()=>_selectedHeightFt=v!), suffix: 'Ft')),
                const SizedBox(width: 12),
                Expanded(child: _buildDropdown(List.generate(12, (i)=>i.toString()), _selectedHeightInch, (v)=>setState(()=>_selectedHeightInch=v!), suffix: 'Inch')),
              ],
            ),
            
            const SizedBox(height: 24),
            _buildLabel('Weight (kg)'),
            _buildTextField(_weightController, 'e.g. 70', kType: TextInputType.number, icon: Icons.monitor_weight_outlined),
            
            const SizedBox(height: 48),
            _buildSaveButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(title, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
  );

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
  );

  Widget _buildTextField(TextEditingController ctrl, String hint, {int maxLines = 1, IconData? icon, TextInputType? kType}) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: kType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(16),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white24, size: 20) : null,
      ),
    ),
  );

  Widget _buildDOBField(TextEditingController ctrl, String hint) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: TextField(
      controller: ctrl,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );

  Widget _buildDropdown(List<String> items, String cur, Function(String?) onChange, {String? suffix}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: cur,
        dropdownColor: const Color(0xFF1A1A1A),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white24),
        isExpanded: true,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(suffix != null ? '$e $suffix' : e))).toList(),
        onChanged: onChange,
      ),
    ),
  );

  Widget _buildToggleButton(String label, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: sel ? Colors.orangeAccent : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: sel ? null : Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Center(
        child: Text(label, style: TextStyle(color: sel ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
      ),
    ),
  );

  Widget _buildSaveButton() => InkWell(
    onTap: _isLoading ? null : _saveProfile,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Center(
        child: _isLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
            : const Text('Save Profile Changes', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    ),
  );
}
