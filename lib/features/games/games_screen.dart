import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';
import '../laundry/laundry_screen.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    children: [
      Text(
        'Take a play break',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const Text('Three facilities. Live availability. No game notifications.'),
      const SizedBox(height: 24),
      const ActiveSessions(kind: 'sports'),
      AsyncView(
        value: ref.watch(resourcesProvider('sports')),
        builder: (s) => Column(
          children: [
            if (s.metadata.isFromCache)
              const Panel(
                child: Text(
                  'Offline or reconnecting · Last known availability',
                ),
              ),
            if (s.docs.isEmpty)
              const Panel(
                child: Text('Equipment has not been initialized yet.'),
              ),
            ...s.docs.map(
              (d) => ResourceCard(
                resource: Resource.fromDoc(d),
                kind: 'sports',
                offline: s.metadata.isFromCache,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
