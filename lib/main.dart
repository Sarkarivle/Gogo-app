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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initialize();
  
  // Initialize Global Socket Service
  SocketService().init();

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
      home: initialScreen,
    );
  }
}
