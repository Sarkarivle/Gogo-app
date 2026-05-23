import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/location_permission_screen.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'services/user_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initialize();
  
  // Initialize Global Socket Service
  SocketService().init();
  
  // Track App Open
  UserRepository().trackEvent('app_open');

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF2A0D17),
    statusBarIconBrightness: Brightness.light,
  ));
  
  final prefs = await SharedPreferences.getInstance();
  final userDataStr = prefs.getString('user_data');
  
  Widget initialScreen = const LoginScreen();
  
  if (userDataStr != null) {
    final userData = jsonDecode(userDataStr);
    // Agar hasCompletedOnboarding false hai ya missing hai, toh onboarding dikhao
    if (userData['hasCompletedOnboarding'] == true) {
      initialScreen = const HomeScreen();
    } else {
      initialScreen = const LocationPermissionScreen();
    }
  }
  
  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gogo',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      builder: (context, child) {
        return SocketGlobalHandler(child: child!);
      },
      home: initialScreen,
    );
  }
}

class SocketGlobalHandler extends StatefulWidget {
  final Widget child;
  const SocketGlobalHandler({super.key, required this.child});

  @override
  State<SocketGlobalHandler> createState() => _SocketGlobalHandlerState();
}

class _SocketGlobalHandlerState extends State<SocketGlobalHandler> {
  @override
  void initState() {
    super.initState();
    _listenToSocketEvents();
  }

  void _listenToSocketEvents() {
    SocketService().eventStream.listen((event) {
      final String type = event['event'];
      final dynamic data = event['data'];

      if (type == 'force_logout') {
        _handleForceLogout(data['reason'] ?? 'Account restricted by moderator');
      } else if (type == 'admin_alert') {
        _showAdminAlert(data['title'], data['message']);
      } else if (type == 'profile_sync_required') {
        _handleProfileSync(data);
      }
    });
  }

  void _handleForceLogout(String reason) async {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    // Clear local data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    SocketService().dispose();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Access Restricted', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _showAdminAlert(String? title, String? message) {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(message ?? ''),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _handleProfileSync(Map<String, dynamic> data) async {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;

    // Determine the message based on changes
    String title = "Account Updated";
    String message = "Your profile has been updated by the administrator.";
    
    if (data['isPremium'] == true) {
      title = "Premium Unlocked! 🚀";
      message = "Congratulations! You now have full access to all premium features.";
    } else if (data['isVerified'] == true) {
      title = "Profile Verified! ✅";
      message = "Your account has been successfully verified.";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () async {
              // 1. Update Local Storage
              final prefs = await SharedPreferences.getInstance();
              final userDataStr = prefs.getString('user_data');
              if (userDataStr != null) {
                Map<String, dynamic> userData = jsonDecode(userDataStr);
                if (data.containsKey('fullUser')) {
                  userData = data['fullUser'];
                } else {
                  if (data.containsKey('isPremium')) userData['isPremium'] = data['isPremium'];
                  if (data.containsKey('isVerified')) userData['isVerified'] = data['isVerified'];
                  if (data.containsKey('isShadowBanned')) userData['isShadowBanned'] = data['isShadowBanned'];
                  if (data.containsKey('accountStatus')) userData['accountStatus'] = data['accountStatus'];
                }
                await prefs.setString('user_data', jsonEncode(userData));
                
                // 2. Refresh App State
                UserRepository().updateLocalUser(userData);
                SocketService().updateCurrentUser(userData['phone']);
              }

              // 3. Restart App Navigation to refresh all screens
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            child: const Text('OK', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
