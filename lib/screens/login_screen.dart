import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'onboarding/location_permission_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isOlderThan18 = true;
  String? _verificationId;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _sendOTP() async {
    if (_phoneController.text.length < 10) {
      _showSnackBar('Please enter a valid mobile number');
      return;
    }
    if (!_isOlderThan18) {
      _showSnackBar('You must be 18+ to use this app');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+91${_phoneController.text.trim()}',
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          _handleBackendLogin(_phoneController.text.trim());
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showSnackBar('Verification Failed: ${e.message}');
        },
        codeSent: (String verId, int? resendToken) {
          setState(() {
            _verificationId = verId;
            _isLoading = false;
          });
          _showOTPDialog();
        },
        codeAutoRetrievalTimeout: (String verId) => _verificationId = verId,
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length < 6) return;
    setState(() => _isLoading = true);
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await _auth.signInWithCredential(credential);
      Navigator.pop(context); // Close dialog
      _handleBackendLogin(_phoneController.text.trim());
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Invalid OTP');
    }
  }

  Future<void> _handleBackendLogin(String phone) async {
    try {
      // Step 1: Attempt Login
      final response = await ApiService.post('/api/login', {'phone': phone});
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        _saveUserAndGoHome(data['user']);
      } else {
        // Step 2: Auto-Register if not found
        final regResponse = await ApiService.post('/api/register', {
          'phone': phone,
          'name': 'User ${phone.substring(phone.length - 4)}',
          'age': 18,
          'isPremium': false,
          'hasCompletedOnboarding': false
        });
        final regData = jsonDecode(regResponse.body);
        if (regData['success'] == true) {
          _saveUserAndGoHome(regData['user']);
        } else {
          _showSnackBar('Registration failed. Please try later.');
        }
      }
    } catch (e) {
      debugPrint('Login Error: $e');
      _showSnackBar('Connection failed. Is server running on 5000?');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserAndGoHome(dynamic userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(userData));
    await NotificationService.updateTokenToServer();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LocationPermissionScreen()));
    }
  }

  // UI Helper methods (SnackBar, Dialog, build) remain same...
  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showOTPDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Enter OTP', style: TextStyle(color: Colors.orangeAccent)),
        content: TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(filled: true, fillColor: Colors.white10),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _verifyOTP, child: const Text('VERIFY')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(40))),
              child: const Icon(Icons.people_rounded, size: 100, color: Color(0xFF6C63FF)),
            ),
            Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                children: [
                  const Text('GoGo - Gay Dating', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Mobile No',
                      prefixText: '+91 ',
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.orangeAccent)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity, height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendOTP,
                      child: _isLoading ? const CircularProgressIndicator() : const Text('Get OTP'),
                    ),
                  ),
                  Row(
                    children: [
                      Checkbox(value: _isOlderThan18, onChanged: (val) => setState(() => _isOlderThan18 = val!)),
                      const Text('I am older than 18', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
