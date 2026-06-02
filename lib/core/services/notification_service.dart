import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/network/socket_service.dart';
import 'package:gogo/features/call/providers/call_service.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';
import 'package:gogo/main.dart';
import 'package:gogo/features/chat/screens/chat_screen.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Track unread messages from each sender for local notifications
  static final Map<String, int> _unreadCounts = {};
  
  // Prevent duplicate notifications within a short window
  static final Set<String> _recentlyShownIds = {};

  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

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

    // Create high importance channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chat_messages',
      'Chat Messages',
      description: 'Notifications for new messages and calls.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Listen for Foreground FCM Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("📩 [FCM] Received foreground message: ${message.data}");
      _showLocalNotification(
        title: message.notification?.title ?? "New Message",
        body: message.notification?.body ?? "",
        data: message.data,
      );
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
    if (data['senderPhone'] != null) {
      final phone = data['senderPhone'].toString();
      _unreadCounts[phone] = 0; // Clear count when navigating

      final context = MyApp.navigatorKey.currentContext;
      if (context != null) {
        if (data['type'] == 'call') {
          // If it was a call notification, we don't necessarily navigate to chat,
          // but maybe just let them see the missed call log in inbox.
        } else {
          ChatPage.navigate(
            context,
            name: data['senderName'] ?? "User",
            receiverPhone: phone,
            distance: "Nearby",
            position: data['senderPosition'] ?? "Member",
          );
        }
      }
    }
  }

  static void clearUnreadForSender(String phone) {
    _unreadCounts[phone] = 0;
  }

  static Future<void> updateTokenToServer() async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) {
        return;
      }
      debugPrint("🔑 FCM Token: $token");

      final user = UserRepository().currentUser;
      if (user != null) {
        await ApiService.post('/api/user/update-fcm', {
          'phone': user['phone'],
          'fcmToken': token,
        });
      }
    } catch (e) {
      debugPrint("FCM Token update error: $e");
    }
  }

  static void showLocalNotificationFromSocket(Map<String, dynamic> data) {
    final String senderPhone = data['senderPhone'] ?? '';
    final String senderName = data['senderName'] ?? 'User';
    final String type = data['type'] ?? 'text';
    final String message = data['message'] ?? '';
    final String roomId = data['roomId'] ?? '';
    final String messageId = data['_id'] ?? data['messageId'] ?? '';
    
    String body = '';
    if (type == 'image') {
      body = '📷 Sent an image';
    } else if (type == 'audio') {
      body = '🎵 Sent a voice message';
    } else if (type == 'video') {
      body = '🎥 Sent a video';
    } else {
      body = message;
    }

    _showLocalNotification(
      title: senderName,
      body: body,
      data: {
        'type': 'chat',
        'senderPhone': senderPhone,
        'senderName': senderName,
        'roomId': roomId,
        'messageId': messageId,
      },
    );
  }

  static void showCallNotification(Map<String, dynamic> data) {
    if (CallService().state != CallState.idle) {
      return;
    }

    _showLocalNotification(
      title: "Incoming Call",
      body: "${data['callerName'] ?? 'Someone'} is calling...",
      data: {
        'type': 'call',
        'senderPhone': data['callerPhone'],
        'senderName': data['callerName'],
      },
    );
  }

  static void _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    final String? senderPhone = data['senderPhone']?.toString();
    final String? roomId = data['roomId']?.toString();
    final String? messageId = data['messageId']?.toString();

    // 1. Protection: If we are already in THIS chat room, don't show notification
    if (roomId != null && SocketService().activeRoomId == roomId) {
      debugPrint("🚫 [Notification] Skipping: Already in room $roomId");
      return;
    }

    // 2. Protection: Duplicate check for FCM vs Socket
    if (messageId != null) {
      if (_recentlyShownIds.contains(messageId)) {
        debugPrint("🚫 [Notification] Skipping duplicate: $messageId");
        return;
      }
      _recentlyShownIds.add(messageId);
      if (_recentlyShownIds.length > 50) {
        _recentlyShownIds.remove(_recentlyShownIds.first);
      }
    }

    String finalTitle = title;
    String finalBody = body;

    if (senderPhone != null && data['type'] == 'chat') {
      _unreadCounts[senderPhone] = (_unreadCounts[senderPhone] ?? 0) + 1;
      int count = _unreadCounts[senderPhone]!;
      
      if (count > 1) {
        finalTitle = "$title ($count messages)";
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      ticker: 'new message',
    );
    
    final details = NotificationDetails(android: androidDetails);
    
    // Use senderPhone hash as ID to update the same notification for that sender
    int id = senderPhone?.hashCode ?? 0;

    _localNotifications.show(
      id,
      finalTitle,
      finalBody,
      details,
      payload: jsonEncode(data),
    );
  }
}
