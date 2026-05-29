import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'onboarding/location_permission_screen.dart';
import '../services/user_repository.dart';
import '../services/app_config_service.dart';
import '../services/premium_service.dart';

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
      // Re-fetch Standard Mode status on login to ensure accuracy
      await AppConfigService().fetchReviewMode();
      
      final String? firebaseToken = await _auth.currentUser?.getIdToken();

      final response = await ApiService.post('/api/user/login', {
        'phone': phone,
        'firebaseToken': firebaseToken,
      });
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _saveUserAndGoHome(data['user'], data['token']);
      } else {
        final regResponse = await ApiService.post('/api/user/register', {
          'phone': phone,
          'name': 'User ${phone.substring(phone.length - 4)}',
          'age': 18,
          'isPremium': false,
          'hasCompletedOnboarding': false,
          'firebaseToken': firebaseToken,
        });
        final regData = jsonDecode(regResponse.body);
        if (regData['success'] == true) {
          _saveUserAndGoHome(regData['user'], regData['token']);
        } else {
          _showSnackBar('Registration failed. Please try later.');
        }
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('Exception: ')) {
        errorMsg = errorMsg.split('Exception: ').last;
      }
      _showSnackBar(errorMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserAndGoHome(dynamic userData, String? token) async {
    final prefs = await SharedPreferences.getInstance();
    
    // If Review Mode is active, force premium status locally for a seamless experience
    if (AppConfigService().isStandardMode) {
      userData['isPremium'] = true;
      userData['premiumExpiry'] = DateTime.now().add(const Duration(days: 365)).toIso8601String();
      await PremiumService().init();
    }

    await prefs.setString('user_data', jsonEncode(userData));
    if (token != null) {
      await prefs.setString('auth_token', token);
    }
    await NotificationService.updateTokenToServer();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LocationPermissionScreen()));
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      resizeToAvoidBottomInset: true, // कीबोर्ड आने पर लेआउट को एडजस्ट करने दें
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
              decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
              child: AutofillGroup( // पूरे फॉर्म को इसमें डाला
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(_showOTPView ? 'GoGo - Gay Dating' : 'Welcome to GoGo', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 10),
                      Text(
                        _showOTPView 
                          ? '6 digit OTP has been sent to your mobile number\n+91 ${_phoneController.text}. Please wait'
                          : 'Connect with people nearby',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      const SizedBox(height: 40),
                      
                      if (!_showOTPView) _buildPhoneInput() else _buildOTPInput(),
                      
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity, height: 60,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : (_showOTPView ? _verifyOTP : _sendOTP),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0),
                          child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : Text(_showOTPView ? 'VERIFY' : 'Get OTP', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_showOTPView) ...[
                        const SizedBox(height: 20),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("Resend OTP in ", style: TextStyle(color: Colors.white38, fontSize: 13)), Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: Text('$_resendTimerCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))]),
                        const SizedBox(height: 15),
                        TextButton(onPressed: () => setState(() => _showOTPView = false), child: const Text('re-enter phone number', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline))),
                      ],
                      const SizedBox(height: 30),
                      _buildPolicyText(),
                      const SizedBox(height: 20),
                    ],
                  ),
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
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Mobile No', hintStyle: const TextStyle(color: Colors.white10),
            prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 15, vertical: 14), child: Text('+91 ', style: TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold))),
            filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 15),
        Row(children: [Checkbox(value: _isOlderThan18, activeColor: Colors.orangeAccent, onChanged: (val) => setState(() => _isOlderThan18 = val!)), const Text('I am older than 18', style: TextStyle(color: Colors.white70))]),
      ],
    );
  }

  Widget _buildOTPInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) => SizedBox(
        width: 45, height: 55,
        child: TextField(
          controller: _otpControllers[index], focusNode: _focusNodes[index],
          keyboardType: TextInputType.number, textAlign: TextAlign.center, maxLength: 1,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            counterText: "", 
            contentPadding: EdgeInsets.zero,
            filled: true, 
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), 
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orangeAccent))
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
