import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sms_autofill/sms_autofill.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/auth/screens/location_permission_screen.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/auth/repositories/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with CodeAutoFill {
  final _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(4, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());
  
  bool _isLoading = false;
  bool _showOTPView = false;
  int _resendTimerCount = 30;
  Timer? _timer;
  String? _currentReqId;
  Map<String, String> policyUrls = {};

  static const _channel = MethodChannel('com.gogo.app/phone_hint');

  @override
  void codeUpdated() {
    if (code != null && code!.length == 4) {
      if (mounted) {
        setState(() {
          for (int i = 0; i < 4; i++) {
            _otpControllers[i].text = code![i];
          }
        });
        _verifyOTP();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    UserRepository().trackEvent('login_page_open');
    listenForCode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPhoneHint();
    });
    _fetchPolicies();
  }

  @override
  void dispose() {
    cancel();
    _phoneController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _resendTimerCount = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimerCount == 0) {
        timer.cancel();
      } else if (mounted) {
        setState(() => _resendTimerCount--);
      }
    });
  }

  Future<void> _fetchPolicies() async {
    try {
      final response = await ApiService.get('/api/user/policies');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List policies = data['policies'];
          setState(() {
            for (var p in policies) {
              policyUrls[p['type']] = p['url'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching policies: $e');
    }
  }

  Future<void> _launchUrl(String type) async {
    final urlString = policyUrls[type];
    if (urlString == null || urlString.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link not available yet')));
      }
      return;
    }
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch link')));
      }
    }
  }

  Future<void> _showPhoneHint() async {
    try {
      final String? result = await _channel.invokeMethod('showPhoneHint');
      if (result != null && result.isNotEmpty) {
        String digits = result.replaceAll(RegExp(r'[^0-9]'), '');
        String finalNumber = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
        setState(() => _phoneController.text = finalNumber);
        if (finalNumber.length == 10) {
          _sendOTP();
        }
      }
    } catch (e) {
      debugPrint("Phone hint error: $e");
    }
  }

  Future<void> _sendOTP() async {
    String phone = _phoneController.text.trim();
    if (phone.length < 10) {
      return _showSnackBar('Please enter a valid mobile number');
    }
    
    setState(() => _isLoading = true);
    try {
      final result = await AuthRepository().sendOTP(phone);
      if (result['success'] == true) {
        setState(() {
          _isLoading = false;
          _showOTPView = true;
          _currentReqId = result['reqId'];
        });
        _startTimer();
      } else {
        setState(() => _isLoading = false);
        _showSnackBar(result['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _verifyOTP() async {
    String otp = _otpControllers.map((e) => e.text).join();
    if (otp.length < 4) return;
    
    setState(() => _isLoading = true);
    final String phone = _phoneController.text.trim();
    
    try {
      final result = await AuthRepository().handleBackendLogin(phone, otp: otp, reqId: _currentReqId);
      if (result['success'] == true) {
        await AuthRepository().saveSession(result['user'], result['token']);
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LocationPermissionScreen()));
      } else if (result['needsRegistration'] == true) {
        _handleAutoRegister(phone, otp);
      } else {
        _showSnackBar(result['message'] ?? 'Invalid OTP');
      }
    } catch (e) {
      _showSnackBar('Verification failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAutoRegister(String phone, String otp) async {
    final regResult = await AuthRepository().registerUser(
      phone: phone, 
      otp: otp, 
      reqId: _currentReqId, 
      name: 'User ${phone.substring(phone.length - 4)}', 
      gender: 'Male'
    );
    if (regResult['success'] == true) {
      await AuthRepository().saveSession(regResult['user'], regResult['token']);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LocationPermissionScreen()));
    } else {
      _showSnackBar(regResult['message'] ?? 'Registration failed');
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // 1. Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A0D17), Color(0xFF0F0F0F), Color(0xFF0F0F0F)],
                ),
              ),
            ),
          ),
          
          // 2. Image Overlay
          Positioned(
            top: 0, left: 0, right: 0,
            child: Opacity(
              opacity: 0.2,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.4,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      ApiService.getSecureUrl(AppConfigService().loginImageUrl).isNotEmpty 
                          ? ApiService.getSecureUrl(AppConfigService().loginImageUrl) 
                          : 'https://img.freepik.com/free-vector/flat-lgbt-community-illustration_23-2148906969.jpg'
                    ), 
                    fit: BoxFit.cover
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: AutofillGroup(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: MediaQuery.of(context).viewInsets.bottom > 0 
                          ? 50 
                          : MediaQuery.of(context).size.height * 0.25,
                    ),
                    
                    Text(
                      _showOTPView ? 'Verify Identity' : 'Welcome to GoGo', 
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _showOTPView 
                        ? 'Enter code sent to +91 ${_phoneController.text}'
                        : 'Connect with amazing people nearby',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6), height: 1.4),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Input Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        children: [
                          if (!_showOTPView) _buildPhoneInput() else _buildOTPInput(),
                          const SizedBox(height: 24),
                          
                          SizedBox(
                            width: double.infinity, height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : (_showOTPView ? _verifyOTP : _sendOTP),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pinkAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoading 
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : Text(_showOTPView ? 'VERIFY' : 'GET OTP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    if (_showOTPView) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [
                          Text("Resend OTP in ", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)), 
                          Text('$_resendTimerCount', style: const TextStyle(color: Colors.pinkAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text("s", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                        ]
                      ),
                      TextButton(
                        onPressed: () => setState(() => _showOTPView = false), 
                        child: Text('Change phone number', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13))
                      ),
                    ],
                    
                    const SizedBox(height: 40),
                    _buildPolicyText(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Phone Number', 
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 16, right: 10), 
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🇮🇳', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text('+91', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  VerticalDivider(color: Colors.white10, indent: 15, endIndent: 15, width: 1),
                ],
              ),
            ),
            filled: true, 
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.pinkAccent.withValues(alpha: 0.5))),
          ),
        ),
      ],
    );
  }

  Widget _buildOTPInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        return SizedBox(
          width: 55,
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: "",
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.pinkAccent.withValues(alpha: 0.5))),
            ),
            onChanged: (value) {
              if (value.isNotEmpty && index < 3) {
                _focusNodes[index + 1].requestFocus();
              } else if (value.isEmpty && index > 0) {
                _focusNodes[index - 1].requestFocus();
              }
              if (_otpControllers.every((c) => c.text.isNotEmpty)) {
                _verifyOTP();
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildPolicyText() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          children: [
            const TextSpan(text: "By signing in, you agree to our "),
            TextSpan(
              text: "Terms of Service", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline), 
              recognizer: TapGestureRecognizer()..onTap = () => _launchUrl('terms_conditions')
            ),
            const TextSpan(text: " and\n"),
            TextSpan(
              text: "Privacy Policy", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline), 
              recognizer: TapGestureRecognizer()..onTap = () => _launchUrl('privacy_policy')
            ),
          ],
        ),
      ),
    );
  }
}
