import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';
import '../notifications/notifications.dart';

class LaundryScreen extends ConsumerStatefulWidget {
  const LaundryScreen({super.key});
  @override
  ConsumerState<LaundryScreen> createState() => _LaundryScreenState();
}

class _LaundryScreenState extends ConsumerState<LaundryScreen> {
  String? building;
  int floor = 1;
  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Text(
        'Laundry, made simple',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const Text('Choose a building and check a machine before you head down.'),
      const SizedBox(height: 24),
      const ActiveSessions(kind: 'laundry'),
      const DryingDecisionCards(),
      const DryingCards(),
      AsyncView(
        value: ref.watch(resourcesProvider('laundry')),
        builder: (snapshot) {
          final machines = snapshot.docs.map(Resource.fromDoc).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.metadata.isFromCache)
                const Panel(
                  child: Text(
                    'Offline or reconnecting · Showing last known availability. Wait for a server connection to reserve.',
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: ['HS1', 'HS2', 'KENNEDY', 'DJ', 'MB'].map((id) {
                  final list = machines
                      .where((m) => m.buildingId == id)
                      .toList();
                  return SizedBox(
                    width: 220,
                    child: Card(
                      color: building == id
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() {
                          building = id;
                          floor = 1;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.apartment_rounded),
                              const SizedBox(height: 12),
                              Text(
                                buildingName(id),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text('${list.length} machines'),
                              Text(
                                '${list.where((m) => m.status == Availability.available).length} available · ${list.where((m) => m.status == Availability.inUse).length} in use',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (building != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  children: List.generate(
                    ['DJ', 'MB'].contains(building) ? 4 : 2,
                    (i) => ChoiceChip(
                      label: Text('Floor ${i + 1}'),
                      selected: floor == i + 1,
                      onSelected: (_) => setState(() => floor = i + 1),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...machines
                    .where((m) => m.buildingId == building && m.floor == floor)
                    .map(
                      (m) => ResourceCard(
                        resource: m,
                        kind: 'laundry',
                        offline: snapshot.metadata.isFromCache,
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    ],
  );
}

class ResourceCard extends ConsumerWidget {
  final Resource resource;
  final String kind;
  final bool offline;
  const ResourceCard({
    super.key,
    required this.resource,
    required this.kind,
    required this.offline,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider(kind)).asData?.value ?? [];
    final own = sessions.where((s) => s.resourceId == resource.id).firstOrNull;
    final status = resource.status;
    final color = switch (status) {
      Availability.available => const Color(0xff15803d),
      Availability.inUse => const Color(0xffdc2626),
      Availability.outOfService => Colors.grey,
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                kind == 'laundry'
                    ? Icons.local_laundry_service_outlined
                    : Icons.sports_tennis,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  resource.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          Text(
            '${buildingName(resource.buildingId)}${resource.floor > 0 ? ' · Floor ${resource.floor}' : ''}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 8),
              Text(switch (status) {
                Availability.available => 'Available',
                Availability.inUse => 'In Use',
                Availability.outOfService => 'Out of Service',
              }, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          if (resource.startedAt != null) Elapsed(since: resource.startedAt!),
          const SizedBox(height: 12),
          if (status == Availability.available)
            ActionButton(
              label: kind == 'laundry' ? 'Start Washing' : 'Start Playing',
              onPressed:
                  offline || !ref.read(repositoryProvider).mutationsEnabled
                  ? null
                  : () async {
                      if (!await confirm(
                        context,
                        'Start ${kind == 'laundry' ? 'washing' : 'playing'}?',
                        'Please confirm that the equipment is physically available.',
                      )) {
                        return;
                      }
                      if (kind == 'laundry' && context.mounted) {
                        await Notifications.instance.offerPermission(
                          context,
                          ref.read(repositoryProvider),
                        );
                      }
                      await ref.read(repositoryProvider).call('start', {
                        'kind': kind,
                        'resourceId': resource.id,
                        'requestId': const Uuid().v4(),
                      });
                    },
            ),
          if (own != null)
            ActionButton(
              label: kind == 'laundry' ? 'Finish Washing' : 'Finish Playing',
              onPressed: () => finishSession(context, ref, kind, own),
            ),
          if (own == null)
            TextButton.icon(
              onPressed: () => reportStatus(context, ref, kind, resource.id),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report Incorrect Status'),
            ),
        ],
      ),
    );
  }
}

Future<void> finishSession(
  BuildContext context,
  WidgetRef ref,
  String kind,
  Session session,
) async {
  if (!await confirm(
    context,
    'Finish ${kind == 'laundry' ? 'washing' : 'playing'}?',
    'This will make the equipment available to other students.',
  )) {
    return;
  }
  await ref.read(repositoryProvider).call('finish', {
    'kind': kind,
    'sessionId': session.id,
  });
  if (kind == 'laundry' && context.mounted) {
    final drying = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Drying outside?'),
        content: const Text('Have you placed your clothes outside for drying?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Yes, Drying Outside'),
          ),
        ],
      ),
    );
    if (drying == true) {
      await ref.read(repositoryProvider).call('drying', {
        'sessionId': session.id,
      });
    } else if (drying == false) {
      await ref.read(repositoryProvider).call('skipDrying', {
        'sessionId': session.id,
      });
    }
  }
}

class DryingDecisionCards extends ConsumerWidget {
  const DryingDecisionCards({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return StreamBuilder(
      stream: repo.db
          .collection('laundrySessions')
          .where('sessionOwnerId', isEqualTo: repo.uid)
          .where('status', isEqualTo: 'completed')
          .where('dryingDecision', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(errorText(snapshot.error!));
        return Column(
          children: (snapshot.data?.docs ?? [])
              .map(
                (doc) => Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Washing finished: ${doc.get('resourceId')}'),
                      const Text(
                        'Have you placed your clothes outside for drying?',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionButton(
                            label: 'Yes, Drying Outside',
                            onPressed: () async {
                              await repo.call('drying', {'sessionId': doc.id});
                            },
                          ),
                          ActionButton(
                            label: 'No',
                            onPressed: () async {
                              await repo.call('skipDrying', {
                                'sessionId': doc.id,
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

Future<void> reportStatus(
  BuildContext context,
  WidgetRef ref,
  String kind,
  String id,
) async {
  const reasons = [
    'Machine is actually free',
    'Machine is occupied but marked available',
    'Machine is broken',
    'Other problem',
  ];
  final reason = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Report Incorrect Status'),
      children: reasons
          .map(
            (r) => SimpleDialogOption(
              onPressed: () => Navigator.pop(c, r),
              child: Text(
                kind == 'sports' ? r.replaceAll('Machine', 'Equipment') : r,
              ),
            ),
          )
          .toList(),
    ),
  );
  if (reason == null || !context.mounted) return;
  final description = await input(context, 'Optional description');
  if (description == null) return;
  try {
    await ref.read(repositoryProvider).call('reportStatus', {
      'kind': kind,
      'resourceId': id,
      'reason': reason,
      'description': description,
    });
    if (context.mounted) {
      notice(context, 'Report submitted for administrator review.');
    }
  } catch (e) {
    if (context.mounted) notice(context, errorText(e));
  }
}

class ActiveSessions extends ConsumerWidget {
  final String kind;
  const ActiveSessions({super.key, required this.kind});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView(
    value: ref.watch(sessionsProvider(kind)),
    builder: (sessions) => Column(
      children: sessions
          .map(
            (s) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your active ${kind == 'laundry' ? 'washing' : 'game'} session',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(s.resourceId),
                  Elapsed(since: s.startedAt),
                  ActionButton(
                    label: kind == 'laundry'
                        ? 'Finish Washing'
                        : 'Finish Playing',
                    onPressed: () => finishSession(context, ref, kind, s),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

class DryingCards extends ConsumerWidget {
  const DryingCards({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return StreamBuilder(
      stream: repo.db
          .collection('dryingReminders')
          .where('sessionOwnerId', isEqualTo: repo.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(errorText(snapshot.error!));
        return Column(
          children: (snapshot.data?.docs ?? [])
              .map(
                (doc) => Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clothes drying outside',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'A reminder is scheduled for 12 hours after confirmation.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionButton(
                            label: 'Mark collected',
                            onPressed: () async {
                              await repo.call('cancelDrying', {
                                'sessionId': doc.id,
                                'collected': true,
                              });
                            },
                          ),
                          ActionButton(
                            label: 'Cancel reminder',
                            onPressed: () async {
                              await repo.call('cancelDrying', {
                                'sessionId': doc.id,
                                'collected': false,
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
