// Local, read-only UI preview. Never imported by the production entry point.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hostel_connect/app/app.dart';
import 'package:hostel_connect/core/repository.dart';
import 'package:hostel_connect/features/home/home_screen.dart';
import 'package:hostel_connect/features/laundry/laundry_screen.dart';
import 'package:hostel_connect/features/mess/mess_screen.dart';
import 'package:hostel_connect/features/community/community_screen.dart';
import 'package:hostel_connect/features/games/games_screen.dart';
import 'package:hostel_connect/features/settings/settings_screen.dart';

class PreviewRepository extends Repository {
  PreviewRepository(FirebaseFirestore firestore) : super(firestore: firestore);
  @override
  String get uid => 'preview-resident';
  @override
  bool get mutationsEnabled => false;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    throw FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Read-only preview. Connect Firebase to submit this action.',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = FakeFirebaseFirestore();
  await db.doc('users/preview-resident').set({
    'displayName': 'Resident482',
    'publicId': 'preview-public',
    'reminders': true,
  });
  for (final entry in {
    'HS1': [2, 1],
    'HS2': [2, 1],
    'KENNEDY': [2, 2],
    'DJ': [4, 1],
    'MB': [3, 1],
  }.entries) {
    for (var floor = 1; floor <= entry.value[0]; floor++) {
      for (var n = 1; n <= entry.value[1]; n++) {
        final occupied = floor == 2 && n == 1;
        await db.doc('machines/${entry.key}-F$floor-WM$n').set({
          'buildingId': entry.key,
          'floorNumber': floor,
          'machineNumber': n,
          'status': occupied ? 'inUse' : 'available',
          'startedAt': occupied
              ? Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(minutes: 12)),
                )
              : null,
        });
      }
    }
  }
  for (final e in [
    ['DJ-TT1', 'DJ', 'Table Tennis'],
    ['KENNEDY-TT1', 'KENNEDY', 'Table Tennis'],
    ['KENNEDY-CARROM1', 'KENNEDY', 'Carrom'],
  ]) {
    await db.doc('sportsEquipment/${e[0]}').set({
      'buildingId': e[1],
      'equipmentType': e[2],
      'status': 'available',
      'startedAt': null,
    });
  }
  final menu = jsonDecode(
    await rootBundle.loadString('assets/menu/weekly-menu.json'),
  ) as Map<String, dynamic>;
  for (final e in (menu['days'] as Map<String, dynamic>).entries) {
    await db
        .doc('weeklyMenu/${e.key}')
        .set(Map<String, dynamic>.from(e.value as Map));
  }
  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(PreviewRepository(db))],
      child: const PreviewApp(),
    ),
  );
}

final previewRouter = GoRouter(
  routes: [
    ShellRoute(
      builder: (c, s, child) => AppShell(path: s.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
        GoRoute(path: '/laundry', builder: (c, s) => const LaundryScreen()),
        GoRoute(path: '/mess', builder: (c, s) => const MessScreen()),
        GoRoute(path: '/community', builder: (c, s) => const CommunityScreen()),
        GoRoute(path: '/games', builder: (c, s) => const GamesScreen()),
      ],
    ),
    GoRoute(path: '/help', builder: (c, s) => const HelpScreen()),
    GoRoute(path: '/settings', builder: (c, s) => const PreviewSettings()),
  ],
);

class PreviewApp extends ConsumerWidget {
  const PreviewApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Hostel Connect — Preview',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: ref.watch(themeProvider),
    routerConfig: previewRouter,
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xff312e81),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'READ-ONLY PREVIEW · Sample availability · No live reservations',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}

class PreviewSettings extends ConsumerWidget {
  const PreviewSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Preview settings')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Explore the actual Flutter interface with sample availability and the translated weekly menu. Firebase-dependent actions are disabled in this preview.',
        ),
        const SizedBox(height: 24),
        ...ThemeMode.values.map(
          (mode) => ListTile(
            title: Text('${mode.name} theme'),
            trailing: ref.watch(themeProvider) == mode
                ? const Icon(Icons.check)
                : null,
            onTap: () => ref.read(themeProvider.notifier).change(mode),
          ),
        ),
      ],
    ),
  );
}
