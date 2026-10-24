import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'repository.dart';

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  const AsyncView({super.key, required this.value, required this.builder});
  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (e, _) =>
        Padding(padding: const EdgeInsets.all(20), child: Text(errorText(e))),
  );
}

String errorText(Object e) => e is FirebaseException
    ? (e.message ?? 'Unable to connect. Please try again.')
    : 'Something went wrong. Please try again.';
void notice(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> input(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 500,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLength: maxLength,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Dialog route animations may still reference the controller; dispose after route teardown.
  Future.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class ActionButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  const ActionButton({super.key, required this.label, required this.onPressed});
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy || widget.onPressed == null
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.onPressed!();
            } catch (e) {
              if (context.mounted) notice(context, errorText(e));
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
    child: busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(widget.label),
  );
}

class Elapsed extends ConsumerWidget {
  final DateTime since;
  const Elapsed({super.key, required this.since});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final minutes = DateTime.now().difference(since).inMinutes.clamp(0, 999999);
    return Text('${minutes ~/ 60}h ${minutes % 60}m elapsed');
  }
}
