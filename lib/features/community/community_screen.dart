import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../notifications/notifications.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';

final moderationProvider = StreamProvider<Map<String, int>>(
  (ref) => ref
      .watch(repositoryProvider)
      .db
      .collection('communityModeration')
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: d.get('count') as int}),
);

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final text = TextEditingController(), scroll = ScrollController();
  final Map<String, ChatMessage> messages = {};
  Set<String> blocked = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
  final olderSubscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  DocumentSnapshot<Map<String, dynamic>>? cursor;
  ChatMessage? reply;
  bool sending = false, loading = true, more = true, loadingMore = false;
  String? error, failedId;
  @override
  void initState() {
    super.initState();
    _loadBlocks();
    subscription = ref
        .read(repositoryProvider)
        .db
        .collection('chatMessages')
        .orderBy('timestamp', descending: true)
        .limit(40)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final atBottom = !scroll.hasClients || scroll.offset < 100;
            setState(() {
              for (final d in snapshot.docs) {
                messages[d.id] = ChatMessage.fromDoc(d);
              }
              if (cursor == null && snapshot.docs.isNotEmpty) {
                cursor = snapshot.docs.last;
              }
              loading = false;
              error = null;
            });
            if (atBottom) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scroll.hasClients) {
                  scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          },
          onError: (Object e) {
            if (mounted) {
              setState(() {
                loading = false;
                error = errorText(e);
              });
            }
          },
        );
  }

  Future<void> _loadBlocks() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => blocked = (p.getStringList('blocked') ?? []).toSet());
    }
  }

  Future<void> _older() async {
    if (cursor == null || loadingMore) return;
    setState(() => loadingMore = true);
    try {
      final pageQuery = ref
          .read(repositoryProvider)
          .db
          .collection('chatMessages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(cursor!)
          .limit(40);
      final page = await pageQuery.get();
      if (!mounted) return;
      setState(() {
        for (final d in page.docs) {
          messages[d.id] = ChatMessage.fromDoc(d);
        }
        if (page.docs.isNotEmpty) cursor = page.docs.last;
        more = page.docs.length == 40;
      });
      olderSubscriptions.add(
        pageQuery.snapshots().listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              for (final doc in snapshot.docs) {
                messages[doc.id] = ChatMessage.fromDoc(doc);
              }
            });
          },
          onError: (Object e) {
            if (mounted) notice(context, errorText(e));
          },
        ),
      );
    } catch (e) {
      if (mounted) notice(context, errorText(e));
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    for (final listener in olderSubscriptions) {
      listener.cancel();
    }
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() => sending = true);
    final id = failedId ?? const Uuid().v4();
    try {
      await ref.read(repositoryProvider).call('sendMessage', {
        'content': text.text.trim(),
        'replyTo': reply?.id,
        'requestId': id,
      });
      text.clear();
      if (mounted) {
        setState(() {
          reply = null;
          failedId = null;
        });
      }
    } catch (e) {
      failedId = id;
      if (mounted) notice(context, 'Not sent. ${errorText(e)}');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _menu(ChatMessage m, bool own) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in [
              'Reply',
              'Copy',
              if (own) 'Delete',
              if (!own) 'Report message',
              if (!own) 'Report user',
              if (!own) 'Mute locally',
            ])
              ListTile(title: Text(a), onTap: () => Navigator.pop(c, a)),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'Reply':
          setState(() => reply = m);
        case 'Copy':
          await Clipboard.setData(ClipboardData(text: m.content));
        case 'Delete':
          if (await confirm(
            context,
            'Delete message?',
            'This removes the text for everyone.',
          )) {
            await ref.read(repositoryProvider).call('deleteMessage', {
              'messageId': m.id,
            });
          }
        case 'Mute locally':
          final p = await SharedPreferences.getInstance();
          setState(() => blocked.add(m.senderKey));
          await p.setStringList('blocked', blocked.toList());
        case 'Report message':
        case 'Report user':
          final reason = await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(
              title: Text(action),
              children:
                  [
                        'Abusive language',
                        'Vulgar content',
                        'Harassment',
                        'Spam',
                        'Threats',
                        'Other',
                      ]
                      .map(
                        (r) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(c, r),
                          child: Text(r),
                        ),
                      )
                      .toList(),
            ),
          );
          if (reason == null || !mounted) return;
          final description = await input(context, 'Optional explanation');
          if (description == null) return;
          await ref.read(repositoryProvider).call('communityReport', {
            'type': action == 'Report user' ? 'user' : 'message',
            'messageId': m.id,
            'reason': reason,
            'description': description,
          });
          if (mounted) {
            notice(
              context,
              'Report submitted. Six different accounts trigger Community removal.',
            );
          }
      }
    } catch (e) {
      if (mounted) notice(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).asData?.value;
    final moderation = ref.watch(moderationProvider);
    final counts = moderation.asData?.value ?? <String, int>{};
    final restricted = (counts['u_${profile?.publicId}'] ?? 0) >= 6;
    final list =
        messages.values
            .where(
              (m) =>
                  !blocked.contains(m.senderKey) &&
                  (counts['m_${m.id}'] ?? 0) < 6 &&
                  (counts['u_${m.senderKey}'] ?? 0) < 6,
            )
            .toList()
          ..sort((a, b) => b.time.compareTo(a.time));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Hostel Community',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (blocked.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final p = await SharedPreferences.getInstance();
                    await p.remove('blocked');
                    setState(() => blocked.clear());
                  },
                  child: const Text('Unmute all'),
                ),
            ],
          ),
        ),
        if (error != null) Text(error!),
        if (moderation.hasError)
          const Text(
            'Community moderation is unavailable. Please retry later.',
          ),
        if (restricted)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Community posting is suspended after six reports from different accounts. Contact your hostel administrator for review.',
            ),
          ),
        TextButton.icon(
          onPressed: () =>
              Notifications.instance.offerCommunityPermission(context),
          icon: const Icon(Icons.notifications_outlined),
          label: const Text('Community notifications'),
        ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: (moderation.isLoading || moderation.hasError)
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty && !loading
              ? const Center(
                  child: Text('Start a conversation with your hostel.'),
                )
              : ListView.builder(
                  controller: scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length + (more ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (i == list.length) {
                      return TextButton(
                        onPressed: loadingMore ? null : _older,
                        child: Text(
                          loadingMore ? 'Loading…' : 'Load earlier messages',
                        ),
                      );
                    }
                    final m = list[i], own = m.senderKey == profile?.publicId;
                    return Align(
                      alignment: own
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Card(
                          color: own
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: InkWell(
                            onLongPress: m.deleted ? null : () => _menu(m, own),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          own ? 'You' : m.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!m.deleted)
                                        IconButton(
                                          tooltip: 'Message actions',
                                          onPressed: () => _menu(m, own),
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (m.replyTo != null)
                                    Text(
                                      '↳ ${messages[m.replyTo]?.content ?? 'Earlier message'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  Text(m.content),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${m.time.toLocal().hour.toString().padLeft(2, '0')}:${m.time.toLocal().minute.toString().padLeft(2, '0')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (reply != null)
          ListTile(
            title: Text('Reply to ${reply!.name}'),
            subtitle: Text(
              reply!.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              onPressed: () => setState(() => reply = null),
              icon: const Icon(Icons.close),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    enabled: !sending && !restricted,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    onChanged: (_) {
                      failedId = null;
                    },
                    decoration: InputDecoration(
                      hintText: 'Message your hostel',
                      counterText: '',
                      errorText: failedId != null
                          ? 'Failed to send. Tap send to retry.'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: sending ? 'Sending' : 'Send message',
                  onPressed: sending || restricted ? null : _send,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
