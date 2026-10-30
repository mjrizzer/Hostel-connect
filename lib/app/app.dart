import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/repository.dart';
import '../core/widgets.dart';
import '../features/home/home_screen.dart';
import '../features/laundry/laundry_screen.dart';
import '../features/mess/mess_screen.dart';
import '../features/community/community_screen.dart';
import '../features/games/games_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/notifications/notifications.dart';

final router = GoRouter(
  initialLocation: '/welcome',
  routes: [
    GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
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
    GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
    GoRoute(path: '/help', builder: (c, s) => const HelpScreen()),
  ],
);
ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff4f46e5),
      brightness: brightness,
      secondary: const Color(0xff06b6d4),
    ),
    scaffoldBackgroundColor: dark
        ? const Color(0xff0f172a)
        : const Color(0xfff8fafc),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xff1e293b) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

class HostelApp extends ConsumerWidget {
  const HostelApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'myHostel',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: ref.watch(themeProvider),
    routerConfig: router,
  );
}

class AppShell extends StatelessWidget {
  final String path;
  final Widget child;
  const AppShell({super.key, required this.path, required this.child});
  @override
  Widget build(BuildContext context) {
    const paths = ['/', '/laundry', '/mess', '/community', '/games'];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'myHostel',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: paths.indexOf(path).clamp(0, 4),
        onDestinationSelected: (i) => context.go(paths[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_laundry_service_outlined),
            label: 'Laundry',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            label: 'Mess',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_tennis),
            label: 'Games',
          ),
        ],
      ),
    );
  }
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  String? error;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    try {
      final repo = ref.read(repositoryProvider);
      await repo.initialize();
      if (!mounted) return;
      context.go('/');
      try {
        await Notifications.instance.initialize(
          repo,
          (path) => router.go(path),
        );
      } catch (_) {
        /* Notification setup is optional and must not block hostel access. */
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.apartment_rounded,
                size: 88,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to\nmyHostel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your laundry, meals, conversations and games. All in one place.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Connecting your anonymous account…'),
              ] else ...[
                Text(error!, textAlign: TextAlign.center),
                FilledButton(onPressed: _start, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
