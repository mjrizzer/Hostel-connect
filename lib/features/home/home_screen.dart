import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';
import '../laundry/laundry_screen.dart';
import '../mess/mess_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final name = ref.watch(profileProvider).asData?.value.name ?? 'Resident';
    return PageBody(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xff4f46e5), Color(0xff087e98)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR HOSTEL, CONNECTED',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hey, $name',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Less waiting. More living.',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.notifications_outlined),
                    label: Text(
                      ref.watch(repositoryProvider).supportsReminders
                          ? 'Reminder settings'
                          : 'Settings',
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => context.push('/help'),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Help'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!ref.watch(repositoryProvider).supportsReminders)
          const Panel(
            child: Text(
              'Live reservations · Free-plan edition\nScheduled laundry reminders are not available.',
            ),
          ),
        const ActiveSessions(kind: 'laundry'),
        const DryingDecisionCards(),
        const DryingCards(),
        AsyncView(
          value: ref.watch(resourcesProvider('laundry')),
          builder: (s) {
            final list = s.docs.map(Resource.fromDoc).toList();
            return Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Laundry at a glance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${list.length} machines · ${list.where((m) => m.status == Availability.available).length} available · ${list.where((m) => m.status == Availability.inUse).length} in use',
                  ),
                  if (s.metadata.isFromCache)
                    const Text('Offline or reconnecting · Last known status'),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/laundry'),
                    icon: const Icon(Icons.local_laundry_service_outlined),
                    label: const Text('View Laundry'),
                  ),
                ],
              ),
            );
          },
        ),
        Text(
          "Today's mess menu",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('${weekdays[hostelNow().weekday - 1]} · ${dateKey(hostelNow())}'),
        const SizedBox(height: 16),
        MenuCards(date: hostelNow()),
        TextButton(
          onPressed: () => context.go('/mess'),
          child: const Text('View Full Menu'),
        ),
        Panel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Hostel Community'),
            subtitle: const Text('Ask a question. Share an update.'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => context.go('/community'),
          ),
        ),
        Panel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sports_tennis),
            title: const Text('Ready for a game?'),
            subtitle: const Text('Table tennis and carrom availability'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => context.go('/games'),
          ),
        ),
      ],
    );
  }
}
