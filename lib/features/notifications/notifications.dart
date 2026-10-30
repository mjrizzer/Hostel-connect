import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repository.dart';
import '../../core/free_plan.dart';
import '../../core/widgets.dart';

class Notifications {
  Notifications._();
  static final instance = Notifications._();
  final messaging = FirebaseMessaging.instance;
  final local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? tokenSubscription;
  Repository? repository;
  Future<void> initialize(
    Repository repo,
    void Function(String) navigate,
  ) async {
    repository = repo;
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) =>
          navigate(r.payload == '/community' ? '/community' : '/laundry'),
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
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'community_messages',
            'Community messages',
            description: 'New messages in your hostel community',
            importance: Importance.high,
          ),
        );
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) =>
          navigate(m.data['route'] == '/community' ? '/community' : '/laundry'),
    );
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      navigate(
        initial.data['route'] == '/community' ? '/community' : '/laundry',
      );
    }
    FirebaseMessaging.onMessage.listen((m) async {
      final n = m.notification;
      final community = m.data['route'] == '/community';
      final prefs = await SharedPreferences.getInstance();
      if (community && !(prefs.getBool('communityNotifications') ?? false)) {
        return;
      }
      if (n != null) {
        await local.show(
          id:
              (m.data['reminderId'] ?? m.messageId ?? 'laundry').hashCode
                  .abs() %
              2147483647,
          title: n.title,
          body: n.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              community ? 'community_messages' : 'laundry_reminders',
              community ? 'Community messages' : 'Laundry reminders',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@drawable/ic_notification',
              styleInformation: community
                  ? MessagingStyleInformation(
                      const Person(name: 'You'),
                      conversationTitle: 'myHostel Community',
                      groupConversation: true,
                      messages: [
                        Message(
                          n.body ?? '',
                          DateTime.now(),
                          Person(name: n.title ?? 'Resident'),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          payload: community ? '/community' : '/laundry',
        );
      }
    });
    tokenSubscription = messaging.onRegistered.listen((token) {
      if (freePlan) return;
      repo
          .call('token', {'token': token})
          .catchError((Object _) => <String, dynamic>{});
    });
    final settings = await messaging.getNotificationSettings();
    if (!freePlan &&
        settings.authorizationStatus == AuthorizationStatus.authorized) {
      await register(repo);
    }
  }

  Future<void> offerCommunityPermission(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final enabled = prefs.getBool('communityNotifications') ?? false;
    final accepted = await confirm(
      context,
      enabled ? 'Turn off Community notifications?' : 'Community notifications',
      enabled ? 'Stop notifications about new Community messages?' : 'Allow notifications for new Community messages? Push delivery is pending server deployment on the current free plan.',
    );
    if (!accepted) return;
    try {
      if (enabled) {
        await messaging.unsubscribeFromTopic('myhostel_community');
        await prefs.setBool('communityNotifications', false);
      } else {
        final permission = await messaging.requestPermission();
        if (permission.authorizationStatus != AuthorizationStatus.authorized &&
            permission.authorizationStatus != AuthorizationStatus.provisional) {
          return;
        }
        await messaging.register();
        final repo = repository!;
        final profile = await repo.db.doc('users/${repo.uid}').get();
        await messaging.subscribeToTopic(
          'myhostel_sender_${profile.get('publicId')}',
        );
        await messaging.subscribeToTopic('myhostel_community');
        await prefs.setBool('communityNotifications', true);
      }
      if (context.mounted) {
        notice(
          context,
          enabled ? 'Community notifications disabled.' : 'Preference saved. Push delivery starts after the server is deployed.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        notice(context, 'Could not update notifications. Please retry.');
      }
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
