import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repository.dart';
import '../../core/widgets.dart';

class Notifications {
  Notifications._();
  static final instance = Notifications._();
  final messaging = FirebaseMessaging.instance;
  final local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? tokenSubscription;
  Future<void> initialize(
    Repository repo,
    void Function(String) navigate,
  ) async {
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => navigate('/laundry'),
    );
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'laundry_reminders',
            'Laundry reminders',
            description: 'Washing and outdoor drying reminders',
            importance: Importance.high,
          ),
        );
    FirebaseMessaging.onMessageOpenedApp.listen((m) => navigate('/laundry'));
    final initial = await messaging.getInitialMessage();
    if (initial != null) navigate('/laundry');
    FirebaseMessaging.onMessage.listen((m) async {
      final n = m.notification;
      if (n != null) {
        await local.show(
          id:
              (m.data['reminderId'] ?? m.messageId ?? 'laundry').hashCode
                  .abs() %
              2147483647,
          title: n.title,
          body: n.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'laundry_reminders',
              'Laundry reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: '/laundry',
        );
      }
    });
    tokenSubscription = messaging.onRegistered.listen((token) {
      repo
          .call('token', {'token': token})
          .catchError((Object _) => <String, dynamic>{});
    });
    final settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await register(repo);
    }
  }

  Future<void> register(Repository repo) async {
    await messaging.register();
  }

  Future<void> offerPermission(
    BuildContext context,
    Repository repo, {
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force && (prefs.getBool('notificationAsked') ?? false)) return;
    if (!context.mounted) return;
    final accepted = await confirm(
      context,
      'Laundry reminders',
      'Allow notifications for a check after 20 minutes of washing and, if you choose, after 12 hours of outdoor drying? The app works without them.',
    );
    await prefs.setBool('notificationAsked', true);
    if (!accepted) return;
    try {
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional) {
        await register(repo);
      }
    } catch (_) {
      if (context.mounted) {
        notice(
          context,
          'Notifications could not be enabled. You can continue and retry in Settings.',
        );
      }
    }
  }
}
