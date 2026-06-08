import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

// Core
import 'package:gogo/core/services/app_visibility_coordinator.dart';
import 'package:gogo/core/services/force_update_coordinator.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/core/services/analytics_service.dart';

// Features
import 'package:gogo/features/auth/screens/login_screen.dart';
import 'package:gogo/features/auth/screens/splash_screen.dart';
import 'package:gogo/features/home/screens/home_screen.dart';
import 'package:gogo/features/call/providers/call_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/features/profile/repositories/moderation_repository.dart';
import 'package:gogo/features/chat/repositories/chat_realtime_repository.dart';
import 'package:gogo/features/chat/repositories/chat_repository.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Parallel Boot: Initialize multiple services at once to save startup time
  await Future.wait([
    Firebase.initializeApp(),
    UserRepository().initialize(),
    AppVisibilityCoordinator().init(),
  ]);
  
  ModerationRepository().init();
  ChatRealtimeRepository().init();
  
  AnalyticsService.logAppOpen();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF2A0D17),
    statusBarIconBrightness: Brightness.light,
  ));
  
  runApp(const RestartWidget(
    child: MyApp(initialScreen: SplashScreen()),
  ));
}

class RestartWidget extends StatefulWidget {
  final Widget child;
  const RestartWidget({super.key, required this.child});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
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
        scaffoldBackgroundColor: const Color(0xFF121212),
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

class _SocketGlobalHandlerState extends State<SocketGlobalHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToSocketEvents();
    _checkUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkUpdate();
      _syncLocationOnResume(); 
    }
  }

  Future<void> _syncLocationOnResume() async {
    final currentUser = UserRepository().currentUser;
    if (currentUser != null && currentUser['phone'] != null) {
      await UserRepository().updateLocation(currentUser['phone']);
    }
  }

  void _checkUpdate({bool forceRefresh = false}) {
    Future.delayed(const Duration(seconds: 1), () {
      final navContext = MyApp.navigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        ForceUpdateCoordinator().checkAndShowUpdate(navContext, forceRefresh: forceRefresh);
      }
    });
  }

  void _listenToSocketEvents() {
    CallService().init();

    SocketService().eventStream.listen((event) async {
      final String type = event['event'];
      final dynamic data = event['data'];

      if (type == 'force_logout') {
        _handleForceLogout(data['reason'] ?? 'Account restricted by moderator');
      } else if (type == 'admin_alert') {
        _showAdminAlert(data['title'], data['message']);
      } else if (type == 'app_config_sync' || type == 'premium_status_refresh') {
        if (data != null && data['phone'] != null) {
          final currentUser = UserRepository().currentUser;
          if (currentUser != null && currentUser['phone'] == data['phone']) {
             await PremiumService().refreshAccessState();

             final navContext = MyApp.navigatorKey.currentContext;
             if (navContext != null && navContext.mounted) {
                final String msg = data['message'] ?? "Account Status Updated! 🚀";
                final String snackType = data['type'] ?? "success";
                
                ScaffoldMessenger.of(navContext).showSnackBar(
                  SnackBar(
                    content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: snackType == "error" ? Colors.red : (snackType == "warning" ? Colors.orange : Colors.green),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
             }
          }
        } else {
          // Global refresh - use the throttled refreshAccessState
          await PremiumService().refreshAccessState();
          _checkUpdate(forceRefresh: true);
        }
      }
else if (type == 'profile_sync_required') {
        _handleProfileSync(data);
      }
    });
  }

  void _handleForceLogout(String reason) async {
    await UserRepository().updateLocalUser({}); // Clear user data in repo
    ChatRepository.clearAllCache();
    ChatRealtimeRepository().dispose();
    SocketService().dispose();

    final navContext = MyApp.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
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
    final navContext = MyApp.navigatorKey.currentContext;
    if (navContext == null) return;

    if (data['type'] == 'LOCATION_UPDATE' || 
        (!data.containsKey('isPremium') && !data.containsKey('isVerified') && !data.containsKey('fullUser'))) {
      return;
    }

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
      context: navContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () async {
              final currentUser = UserRepository().currentUser;
              if (currentUser != null) {
                Map<String, dynamic> updatedData = Map.from(currentUser);
                if (data.containsKey('fullUser')) {
                  updatedData = data['fullUser'];
                } else {
                  if (data.containsKey('isPremium')) updatedData['isPremium'] = data['isPremium'];
                  if (data.containsKey('isVerified')) updatedData['isVerified'] = data['isVerified'];
                  if (data.containsKey('isShadowBanned')) updatedData['isShadowBanned'] = data['isShadowBanned'];
                  if (data.containsKey('accountStatus')) updatedData['accountStatus'] = data['accountStatus'];
                }
                await UserRepository().updateLocalUser(updatedData);
                SocketService().updateCurrentUser(updatedData['phone']);
              }

              final navContext = MyApp.navigatorKey.currentContext;
              if (navContext != null && navContext.mounted) {
                Navigator.of(navContext).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
                );
              }
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
