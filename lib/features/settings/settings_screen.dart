import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repository.dart';
import '../../core/free_plan.dart';
import '../../core/widgets.dart';
import '../notifications/notifications.dart';

final themeProvider = NotifierProvider<ThemePreference, ThemeMode>(
  ThemePreference.new,
);

class ThemePreference extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = ThemeMode.values.byName(p.getString('theme') ?? 'system');
  }

  Future<void> change(ThemeMode mode) async {
    state = mode;
    await (await SharedPreferences.getInstance()).setString('theme', mode.name);
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  NotificationSettings? permission;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (freePlan) return;
    final p = await FirebaseMessaging.instance.getNotificationSettings();
    if (mounted) setState(() => permission = p);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: PageBody(
      children: [
        AsyncView(
          value: ref.watch(profileProvider),
          builder: (p) => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                ActionButton(
                  label: 'Change display name',
                  onPressed: () async {
                    final name = await input(
                      context,
                      'Display name',
                      initial: p.name,
                      maxLength: 32,
                    );
                    if (name != null && name.isNotEmpty) {
                      await ref.read(repositoryProvider).call('profile', {
                        'displayName': name,
                      });
                    }
                  },
                ),
                if (!freePlan)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Laundry reminders'),
                    value: p.reminders,
                    onChanged: (value) async {
                      try {
                        await ref.read(repositoryProvider).call('profile', {
                          'reminders': value,
                        });
                      } catch (e) {
                        if (context.mounted) notice(context, errorText(e));
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Appearance'),
              DropdownButton<ThemeMode>(
                isExpanded: true,
                value: ref.watch(themeProvider),
                items: ThemeMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(switch (m) {
                          ThemeMode.system => 'System',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        }),
                      ),
                    )
                    .toList(),
                onChanged: (m) {
                  if (m != null) ref.read(themeProvider.notifier).change(m);
                },
              ),
            ],
          ),
        ),
        if (freePlan)
          const Panel(
            child: Text(
              'Free-plan version: live reservations are enabled. Washing and drying reminders are not available.',
            ),
          )
        else
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification permission: ${permission?.authorizationStatus.name ?? 'checking'}',
                ),
                ActionButton(
                  label: 'Enable notifications',
                  onPressed: () async {
                    await Notifications.instance.offerPermission(
                      context,
                      ref.read(repositoryProvider),
                      force: true,
                    );
                    await _refresh();
                  },
                ),
                TextButton(
                  onPressed: () => AppSettings.openAppSettings(
                    type: AppSettingsType.notification,
                  ),
                  child: const Text('Open notification settings'),
                ),
                const Text(
                  'Battery restrictions, network conditions, permissions and push delivery can delay or prevent reminders. A reminder never frees a machine automatically.',
                ),
              ],
            ),
          ),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your anonymous account',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'No phone number, email or password is required. Uninstalling, clearing app data or losing this anonymous account may permanently remove access to previous sessions. Contact an administrator if equipment needs to be released.',
              ),
              SizedBox(height: 12),
              Text('Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Availability and community messages are shared with signed-in residents. Reports, session ownership and notification tokens are private. Moderators can investigate reports. Avoid posting personal contact details in the public chat.',
              ),
            ],
          ),
        ),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community guidelines',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Be respectful. No harassment, threats, spam or personal information about others. Report problems for human review. Reports alone do not cause bans. Anonymous account restrictions cannot guarantee permanent bans because accounts can be recreated.',
              ),
            ],
          ),
        ),
        const ListTile(
          title: Text('Hostel Connect'),
          subtitle: Text('Version 1.0.0 · Made for hostel life'),
        ),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help')),
    body: const PageBody(
      children: [
        Panel(
          child: Text(
            'Laundry\nCheck physical availability, then start a session. Only you can finish it. If a machine is incorrectly marked, submit a report; an administrator will review it.',
          ),
        ),
        Panel(
          child: Text(
            'Mess\nThe weekly menu is the default. Approved changes apply only to their selected date and meal. Suggestions need moderator approval.',
          ),
        ),
        Panel(
          child: Text(
            'Community\nUse the message menu to reply, copy, report or mute. Only your own messages can be deleted.',
          ),
        ),
        Panel(
          child: Text(
            'Offline\nCached availability can be out of date. Reservations need server confirmation. Reconnect and retry if an action fails.',
          ),
        ),
      ],
    ),
  );
}
