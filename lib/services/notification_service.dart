import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../screens/chat_screen.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Request Permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Local Notifications Setup
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          _navigateToChat(data);
        }
      },
    );

    // 3. Listen for Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    // 4. Handle Background/Terminated clicks
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateToChat(message.data);
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _navigateToChat(message.data);
      }
    });

    // 5. Update Token to Server
    updateTokenToServer();
  }

  static void _navigateToChat(Map<String, dynamic> data) {
    if (data['type'] == 'chat' && data['senderPhone'] != null) {
      MyApp.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatPage(
            name: data['senderName'] ?? "User",
            receiverPhone: data['senderPhone'],
            distance: "Nearby",
            position: data['senderPosition'] ?? "Member",
          ),
        ),
      );
    }
  }

  static Future<void> updateTokenToServer() async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) return;

      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_data');
      if (userData != null) {
        final user = jsonDecode(userData);
        await http.post(
          Uri.parse('${ApiService.baseUrl}/api/user/update-fcm'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': user['phone'],
            'fcmToken': token,
          }),
        );
      }
    } catch (e) {
      print("FCM Token update error: $e");
    }
  }

  static void _showLocalNotification(RemoteMessage message) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? "New Message",
      message.notification?.body ?? "",
      details,
      payload: jsonEncode(message.data),
    );
  }
}
