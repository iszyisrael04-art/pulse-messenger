import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'avatar.dart';
import 'social_repository.dart';
import 'social_common.dart';
import 'social_download.dart';

class SocialActions extends StatefulWidget {
  const SocialActions({
    super.key,
    required this.store,
    required this.post,
    required this.onChanged,
    this.vertical = false,
  });
  final SocialStore store;
  final SocialRow post;
  final ValueChanged<SocialRow?> onChanged;
  final bool vertical;
  @override
  State<SocialActions> createState() => _SocialActionsState();
}

class _SocialActionsState extends State<SocialActions> {
  bool busy = false;
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      final updated = await widget.store.post(widget.post['id']);
      if (mounted) widget.onChanged(updated);
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> comments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SocialComments(store: widget.store, post: widget.post),
      ),
    );
    if (mounted) await perform(() async {});
  }

  Widget recipientAvatar(SocialRow chat) {
    final repo = widget.store.repo;
    if (chat['kind'] == 'group')
      return const CircleAvatar(child: Icon(Icons.group_outlined));
    final members = (chat['pulse_members'] as List? ?? []).where(
      (m) => m['user_id'] != repo.uid,
    );
    final profile = members.isEmpty
        ? null
        : repo.profiles[members.first['user_id']];
    return PulseAvatar(
      repo: repo,
      path: profile?['avatar_path'],
      name: repo.chatName(chat),
    );
  }

  Future<void> share() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (c) => SizedBox(
        height: 420,
        child: Column(
          children: [
            const ListTile(
              title: Text('Share post'),
              subtitle: Text(
                'Recipients can open the post if its privacy permits.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share outside Pulse'),
              subtitle: const Text(
                'Send a photo, watermarked video or caption to another app',
              ),
              onTap: () {
                Navigator.pop(c);
                perform(
                  () => downloadPulsePost(
                    context,
                    widget.store,
                    widget.post['id'],
                    external: true,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Pulse post ID'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: widget.post['id']));
                if (c.mounted) Navigator.pop(c);
              },
            ),
            Expanded(
              child: ListView(
                children: widget.store.repo.chats
                    .map(
                      (chat) => ListTile(
                        leading: recipientAvatar(chat),
                        title: Text(widget.store.repo.chatName(chat)),
                        onTap: () {
                          Navigator.pop(c);
                          perform(
                            () => widget.store.share(
                              widget.post['id'],
                              chat['id'],
                            ),
                          );
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> menu(String action) async {
    if (action == 'download') {
      await perform(
        () => downloadPulsePost(context, widget.store, widget.post['id']),
      );
    } else if (action == 'edit') {
      final value = await socialPrompt(
        context,
        'Edit caption',
        initial: widget.post['body'],
      );
      if (value != null && mounted)
        await perform(() => widget.store.edit(widget.post['id'], value));
    } else if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete this content?'),
          content: const Text(
            'It will disappear from feeds. Previously downloaded media cannot be erased remotely.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes == true && mounted)
        await perform(
          () => widget.store.edit(widget.post['id'], '', delete: true),
        );
    } else if (action == 'report') {
      final reason = await socialPrompt(
        context,
        'Report this content',
        limit: 1000,
      );
      if (reason != null && reason.isNotEmpty && mounted)
        await perform(() async {
          await widget.store.rpc('report', {
            'p_id': widget.post['id'],
            'p_reason': reason,
          });
        });
    } else if (action == 'block') {
      await perform(() async {
        await widget.store.block(widget.post['author_id']);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final mine = post['author_id'] == widget.store.uid;
    Widget button(
      IconData icon,
      String label,
      VoidCallback action, {
      bool active = false,
    }) => Tooltip(
      message: label,
      child: TextButton(
        onPressed: busy ? null : action,
        style: TextButton.styleFrom(
          foregroundColor: widget.vertical
              ? Colors.white
              : active
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        child: widget.vertical
            ? Column(
                children: [
                  Icon(icon, color: active ? Colors.pinkAccent : Colors.white),
                  Text(label, style: const TextStyle(fontSize: 11)),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(fontSize: 11)),
                ],
              ),
      ),
    );
    final actions = <Widget>[
      button(
        post['liked'] == true ? Icons.favorite : Icons.favorite_border,
        '${post['likes']}',
        () => perform(
          () => widget.store.action(post['id'], 'like', post['liked'] != true),
        ),
        active: post['liked'] == true,
      ),
      button(Icons.chat_bubble_outline, '${post['comments']}', comments),
      button(Icons.share_outlined, 'Share', share),
      button(
        post['saved'] == true ? Icons.bookmark : Icons.bookmark_border,
        'Save',
        () => perform(
          () => widget.store.action(post['id'], 'save', post['saved'] != true),
        ),
        active: post['saved'] == true,
      ),
      button(
        Icons.repeat,
        '${post['reposts']}',
        () => perform(
          () => widget.store.action(
            post['id'],
            'repost',
            post['reposted'] != true,
          ),
        ),
        active: post['reposted'] == true,
      ),
      if (!mine)
        button(
          Icons.person_add_alt_1,
          post['follow_state'] == 'accepted'
              ? 'Following'
              : post['follow_state'] == 'pending'
              ? 'Requested'
              : 'Follow',
          () => perform(() async {
            await widget.store.follow(
              post['author_id'],
              post['follow_state'] == 'none',
            );
          }),
        ),
      PopupMenuButton<String>(
        tooltip: 'Post actions',
        onSelected: busy ? null : menu,
        itemBuilder: (_) => [
          if ((post['media'] as List).isNotEmpty &&
              (mine ||
                  post['allow_download'] != false ||
                  !(post['media'] as List).any((m) => m['kind'] == 'video')))
            const PopupMenuItem(value: 'download', child: Text('Download')),
          if (mine) ...[
            const PopupMenuItem(value: 'edit', child: Text('Edit caption')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ] else ...[
            const PopupMenuItem(value: 'report', child: Text('Report')),
            const PopupMenuItem(value: 'block', child: Text('Block creator')),
          ],
        ],
        icon: Icon(
          Icons.more_horiz,
          color: widget.vertical ? Colors.white : null,
        ),
      ),
    ];
    return widget.vertical
        ? SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: actions,
            ),
          );
  }
}

class SocialComments extends StatefulWidget {
  const SocialComments({super.key, required this.store, required this.post});
  final SocialStore store;
  final SocialRow post;
  @override
  State<SocialComments> createState() => _SocialCommentsState();
}

class _SocialCommentsState extends State<SocialComments> {
  final rows = <SocialRow>[], text = TextEditingController();
  SocialRow? cursor;
  String? error;
  bool loading = false, sending = false, more = true;
  String? pendingId;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading || (!reset && !more)) return;
    setState(() => loading = true);
    try {
      final data = await widget.store.rpc('comments', {
        'p_post': widget.post['id'],
        'p_before': reset ? null : cursor?['created_at'],
        'p_cursor': reset ? null : cursor?['id'],
      });
      if (!mounted) return;
      final page = (data as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      setState(() {
        if (reset) {
          rows.clear();
          cursor = null;
        }
        final ids = rows.map((r) => r['id']).toSet();
        rows.addAll(page.where((r) => ids.add(r['id'])));
        if (page.isNotEmpty) cursor = page.last;
        more = page.length == 30;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() => sending = true);
    pendingId ??= const Uuid().v4();
    try {
      await widget.store.rpc('comment', {
        'p_id': pendingId,
        'p_post': widget.post['id'],
        'p_body': text.text,
        'p_delete': false,
      });
      if (!mounted) return;
      text.clear();
      pendingId = null;
      await load(reset: true);
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      children: [
        ListTile(
          title: const Text('Comments'),
          trailing: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        if (error != null) Text(error!),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length + 1,
            itemBuilder: (_, i) {
              if (i == rows.length)
                return loading
                    ? const Center(child: CircularProgressIndicator())
                    : more || error != null
                    ? TextButton(
                        onPressed: () => load(),
                        child: const Text('Load comments'),
                      )
                    : const SizedBox(height: 12);
              final row = rows[i];
              return ListTile(
                leading: PulseAvatar(
                  repo: widget.store.repo,
                  path: row['avatar_path'],
                  name: row['display_name'],
                  radius: 18,
                ),
                title: Text('@${row['username'] ?? 'pulse_user'}'),
                subtitle: Text(row['body']),
                trailing:
                    row['author_id'] == widget.store.uid ||
                        widget.post['author_id'] == widget.store.uid
                    ? IconButton(
                        tooltip: 'Delete comment',
                        onPressed: () async {
                          try {
                            await widget.store.rpc('comment', {
                              'p_id': row['id'],
                              'p_post': null,
                              'p_body': '',
                              'p_delete': true,
                            });
                            await load(reset: true);
                          } catch (e) {
                            if (context.mounted) socialNotice(context, e);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      )
                    : null,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: text,
                  enabled: !sending,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Write a comment…',
                    counterText: '',
                  ),
                ),
              ),
              IconButton(
                onPressed: sending ? null : send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
