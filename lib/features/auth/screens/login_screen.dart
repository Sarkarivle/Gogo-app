import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
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
  final List<TextEditingController> _otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  
  bool _isLoading = false;
  bool _isOlderThan18 = true;
  String? _verificationId;
  bool _showOTPView = false;
  int _resendTimerCount = 30;
  Timer? _timer;
  Map<String, String> policyUrls = {};

  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const _channel = MethodChannel('com.gogo.app/phone_hint');

  @override
  void codeUpdated() {
    if (code != null && code!.length == 6) {
      debugPrint("OTP Auto-Retrieved: $code");
      if (mounted) {
        setState(() {
          for (int i = 0; i < 6; i++) {
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
    _listenForSms();
    // Show phone hint as soon as screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPhoneHint();
    });
    _fetchPolicies();
  }

  void _listenForSms() async {
    listenForCode();
    // Get and print app signature for production SMS formatting
    SmsAutoFill().getAppSignature.then((signature) {
      debugPrint("App Signature for SMS Retriever API: $signature");
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link not available yet')),
        );
      }
      return;
    }

    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch link')),
        );
      }
    }
  }

  Future<void> _showPhoneHint() async {
    try {
      final String? result = await _channel.invokeMethod('showPhoneHint');
      if (result != null && result.isNotEmpty) {
        // Step 1: Remove all non-digit characters
        String digits = result.replaceAll(RegExp(r'[^0-9]'), '');
        
        // Step 2: Extract last 10 digits if it's an Indian number
        String finalNumber = digits;
        if (digits.length >= 10) {
          finalNumber = digits.substring(digits.length - 10);
        }

        setState(() {
          _phoneController.text = finalNumber;
        });

        // Step 3: Auto-send OTP only if we have exactly 10 digits
        if (finalNumber.length == 10) {
          _sendOTP();
        }
      }
    } on PlatformException catch (e) {
      debugPrint("Phone Hint Error: ${e.message}");
    }
  }

  @override
  void dispose() {
    cancel(); // Cancel SMS listener
    _phoneController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
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
      } else {
        setState(() => _resendTimerCount--);
      }
    });
  }

  Future<void> _sendOTP() async {
    String phone = _phoneController.text.trim();
    if (phone.length < 10) {
      _showSnackBar('Please enter a valid mobile number');
      return;
    }
    
    // Normalize: Add +91 only if no country code is present
    String fullPhoneNumber = phone.startsWith('+') ? phone : '+91$phone';

    if (!_isOlderThan18) {
      _showSnackBar('You must be 18+ to use this app');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          _handleBackendLogin(phone);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showSnackBar('Verification Failed: ${e.message}');
        },
        codeSent: (String verId, int? resendToken) {
          setState(() {
            _verificationId = verId;
            _isLoading = false;
            _showOTPView = true;
          });
          _listenForSms(); // Start listening again when code is sent
          _startTimer();
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
    String otp = _otpControllers.map((e) => e.text).join();
    if (otp.length < 6) return;
    setState(() => _isLoading = true);
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      final String phone = _phoneController.text.trim();
      UserRepository().trackEvent('otp_verified', customId: phone);
      _handleBackendLogin(phone);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Invalid OTP');
    }
  }

  Future<void> _handleBackendLogin(String phone) async {
    try {
      setState(() => _isLoading = true);
      final result = await AuthRepository().handleBackendLogin(phone);
      
      if (result['success'] == true) {
        _saveUserAndGoHome(result['user'], result['token']);
      } else {
        _showSnackBar(result['message'] ?? 'Login failed');
      }
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserAndGoHome(dynamic userData, String? token) async {
    await AuthRepository().saveSession(userData, token);
    if (mounted) {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const LocationPermissionScreen())
      );
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final bool isStandard = AppConfigService().isStandardMode;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // Background Gradient/Image
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2A0D17), // Deep Wine from Onboarding
                    Color(0xFF0F0F0F),
                    Color(0xFF0F0F0F),
                  ],
                ),
              ),
            ),
          ),
          
          // Subtle Image Overlay
          Positioned(
            top: 0, left: 0, right: 0,
            child: Opacity(
              opacity: 0.2, // Reduced from 0.4 to make background less visible
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
                    // Dynamic Spacer that shrinks when keyboard opens
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: MediaQuery.of(context).viewInsets.bottom > 0 
                          ? 50 
                          : MediaQuery.of(context).size.height * 0.25,
                    ),
                    
                    // Welcome Header
                    Text(
                      _showOTPView ? 'Verify Identity' : (isStandard ? 'GoGo' : 'Welcome to GoGo'), 
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _showOTPView 
                        ? 'Enter the 6-digit code sent to\n+91 ${_phoneController.text}'
                        : (isStandard ? 'Sign in to continue' : 'Connect with amazing people nearby'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6), height: 1.4),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Input Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12), // Increased opacity (less transparent)
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        children: [
                          if (!_showOTPView) _buildPhoneInput() else _buildOTPInput(),
                          const SizedBox(height: 24),
                          
                          // Action Button
                          SizedBox(
                            width: double.infinity, height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : (_showOTPView ? _verifyOTP : _sendOTP),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isStandard ? Colors.orangeAccent : Colors.pinkAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoading 
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : Text(_showOTPView ? 'VERIFY' : 'GET OTP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
          autofillHints: const [AutofillHints.telephoneNumber],
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
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.pinkAccent.withValues(alpha: 0.5))),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              height: 24, width: 24,
              child: Checkbox(
                value: _isOlderThan18, 
                activeColor: Colors.pinkAccent, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (val) => setState(() => _isOlderThan18 = val!)
              ),
            ),
            const SizedBox(width: 12),
            Text('I confirm that I am 18 or older', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildOTPInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) => SizedBox(
        width: 42, height: 50,
        child: TextField(
          controller: _otpControllers[index], focusNode: _focusNodes[index],
          keyboardType: TextInputType.number, textAlign: TextAlign.center, maxLength: 1,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            counterText: "", 
            contentPadding: EdgeInsets.zero,
            filled: true, 
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ), 
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: Colors.pinkAccent, width: 1.5),
            ),
          ),
          onChanged: (value) {
            if (value.length == 1 && index < 5) {
              _focusNodes[index + 1].requestFocus();
            }
            if (value.isEmpty && index > 0) {
              _focusNodes[index - 1].requestFocus();
            }
            if (index == 5 && value.isNotEmpty) {
              _verifyOTP();
            }
          },
        ),
      )),
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
