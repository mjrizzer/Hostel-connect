import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';

class MessScreen extends StatefulWidget {
  const MessScreen({super.key});
  @override
  State<MessScreen> createState() => _MessScreenState();
}

class _MessScreenState extends State<MessScreen> {
  DateTime date = hostelNow();
  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Text(
        'Good food, good day',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const Text('Your hostel menu, all week long.'),
      const SizedBox(height: 20),
      Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () =>
                setState(() => date = date.subtract(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${weekdays[date.weekday - 1]} · ${dateKey(date)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () =>
                setState(() => date = date.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      TextButton(
        onPressed: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (selected != null) setState(() => date = selected);
        },
        child: const Text('Choose date'),
      ),
      MenuCards(date: date),
      const SuggestMenuButton(),
    ],
  );
}

class MenuCards extends ConsumerWidget {
  final DateTime date;
  const MenuCards({super.key, required this.date});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(repositoryProvider).db;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('weeklyMenu/${weekdays[date.weekday - 1]}').snapshots(),
      builder: (context, weekly) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('menuOverrides')
                .where('date', isEqualTo: dateKey(date))
                .snapshots(),
            builder: (context, overrides) {
              if (weekly.hasError || overrides.hasError) {
                return Panel(
                  child: Text(errorText(weekly.error ?? overrides.error!)),
                );
              }
              if (!weekly.hasData || !overrides.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final fixed = weekly.data!.data();
              final changes = {
                for (final doc in overrides.data!.docs)
                  doc.get('mealType') as String: doc.data(),
              };
              return Column(
                children: meals.entries.map((entry) {
                  final changed = changes[entry.key];
                  final foods =
                      (changed?['items'] ?? fixed?[entry.key])
                          as List<dynamic>?;
                  return Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(switch (entry.key) {
                              'breakfast' => Icons.wb_sunny_outlined,
                              'lunch' => Icons.restaurant_outlined,
                              'snacks' => Icons.local_cafe_outlined,
                              _ => Icons.nightlight_outlined,
                            }),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (changed != null)
                              const Chip(label: Text('Updated')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          foods?.join(' · ') ??
                              'Official menu awaiting publication.',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
    );
  }
}

class SuggestMenuButton extends ConsumerWidget {
  const SuggestMenuButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActionButton(
    label: 'Suggest Menu Change',
    onPressed: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: hostelNow(),
        firstDate: hostelNow().subtract(const Duration(days: 1)),
        lastDate: hostelNow().add(const Duration(days: 90)),
      );
      if (date == null || !context.mounted) return;
      final meal = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Choose meal'),
          children: meals.entries
              .map(
                (e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, e.key),
                  child: Text(e.value),
                ),
              )
              .toList(),
        ),
      );
      if (meal == null || !context.mounted) return;
      final foods = await input(
        context,
        'New food items (separate with commas)',
        maxLength: 1000,
      );
      if (foods == null || foods.isEmpty || !context.mounted) return;
      final reason = await input(context, 'Optional reason');
      if (reason == null) return;
      await ref.read(repositoryProvider).call('suggestMenu', {
        'date': dateKey(date),
        'mealType': meal,
        'items': foods
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'reason': reason,
      });
      if (context.mounted) {
        notice(context, 'Suggestion pending moderator approval.');
      }
    },
  );
}
