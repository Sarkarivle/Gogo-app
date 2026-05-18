import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

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
    if (_bioController.text.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bio must be at least 20 characters')));
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
          
          // Merge updated data with existing data to ensure nothing is lost
          Map<String, dynamic> existingData = jsonDecode(prefs.getString('user_data') ?? '{}');
          Map<String, dynamic> newData = Map<String, dynamic>.from(data['user']);
          
          // Overwrite only with what the server returned (which includes our updates)
          existingData.addAll(newData);
          
          await prefs.setString('user_data', jsonEncode(existingData));
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
            );
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) { print(e); } finally { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(backgroundColor: const Color(0xFF2A0D17), elevation: 0, title: const Text('Edit Profile'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildLabel('Nickname (not your original name)'),
          _buildTextField(_nameController, 'Nickname', icon: Icons.edit),
          const SizedBox(height: 25),
          _buildLabel('Date of Birth'),
          Row(children: [
            Expanded(child: _buildDOBField(_dayController, 'Day')),
            const SizedBox(width: 12),
            Expanded(child: _buildDOBField(_monthController, 'Month')),
            const SizedBox(width: 12),
            Expanded(child: _buildDOBField(_yearController, 'Year')),
          ]),
          const SizedBox(height: 25),
          _buildLabel('Your Position'),
          _buildDropdown(['Top', 'Bottom', 'Versatile', 'Top, Ver'], _selectedPosition, (v) => setState(() => _selectedPosition = v!)),
          const SizedBox(height: 25),
          _buildLabel('Do you have a place to meet?'),
          Row(children: [
            Expanded(child: _buildToggleButton('YES', _havePlace == 'YES', () => setState(() => _havePlace = 'YES'))),
            const SizedBox(width: 12),
            Expanded(child: _buildToggleButton('NO', _havePlace == 'NO', () => setState(() => _havePlace = 'NO'))),
          ]),
          const SizedBox(height: 25),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildLabel('Bio'),
            const Text('minimum 20 Character', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
          _buildTextField(_bioController, 'Write about yourself...', maxLines: 4),
          const SizedBox(height: 30),
          const Text('Add More Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildDropdown(List.generate(4, (i)=>(i+4).toString()), _selectedHeightFt, (v)=>setState(()=>_selectedHeightFt=v!), suffix: 'Ft')),
            const SizedBox(width: 12),
            Expanded(child: _buildDropdown(List.generate(12, (i)=>i.toString()), _selectedHeightInch, (v)=>setState(()=>_selectedHeightInch=v!), suffix: 'Inch')),
          ]),
          const SizedBox(height: 25),
          _buildTextField(_weightController, 'Weight (kg)', kType: TextInputType.number),
          const SizedBox(height: 50),
          Container(width: double.infinity, height: 55, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)]), borderRadius: BorderRadius.circular(30)), child: Material(color: Colors.transparent, child: InkWell(onTap: _isLoading ? null : _saveProfile, child: Center(child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text('Save', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)))))),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)));
  Widget _buildTextField(TextEditingController ctrl, String hint, {int maxLines = 1, IconData? icon, TextInputType? kType}) => Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: TextField(controller: ctrl, maxLines: maxLines, keyboardType: kType, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24), border: InputBorder.none, contentPadding: const EdgeInsets.all(16), suffixIcon: icon != null ? Icon(icon, color: Colors.white24, size: 18) : null)));
  Widget _buildDOBField(TextEditingController ctrl, String hint) => Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: TextField(controller: ctrl, textAlign: TextAlign.center, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14))));
  Widget _buildDropdown(List<String> items, String cur, Function(String?) onChange, {String? suffix}) => Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: cur, dropdownColor: const Color(0xFF1E1E1E), icon: const Icon(Icons.expand_more, color: Colors.white38), isExpanded: true, style: const TextStyle(color: Colors.white), items: items.map((e) => DropdownMenuItem(value: e, child: Text(suffix != null ? '$e $suffix' : e))).toList(), onChanged: onChange)));
  Widget _buildToggleButton(String label, bool sel, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(height: 50, decoration: BoxDecoration(color: sel ? Colors.orangeAccent : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(label, style: TextStyle(color: sel ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)))));
}
