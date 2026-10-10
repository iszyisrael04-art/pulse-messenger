import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'repository.dart' hide Row;
import 'profile.dart';
import 'admin.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.toggleTheme});
  final VoidCallback toggleTheme;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PulseRepository repo;
  int section = 0;
  final composer = TextEditingController(), search = TextEditingController();
  String? reply;
  bool sending = false;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    repo = PulseRepository(Supabase.instance.client)..addListener(changed);
    repo.initialize();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(changed);
    repo.dispose();
    composer.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      await repo.refresh();
    } on PostgrestException catch (e) {
      notice(e.message);
    } catch (_) {
      notice(
        'Unable to complete this action. Check your connection and try again.',
      );
    }
  }

  Future<String?> prompt(
    String title, {
    String initial = '',
    int lines = 1,
  }) async {
    final text = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: text, maxLines: lines, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, text.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    text.dispose();
    return value;
  }

  Future<void> newChat({bool group = false}) async {
    final usernames = await prompt(
      group
          ? 'Group members (usernames separated by commas)'
          : 'Enter a Pulse username',
    );
    if (usernames == null || usernames.isEmpty) return;
    String name = 'Pulse chat';
    if (group) {
      final n = await prompt('Group name');
      if (n == null || n.isEmpty) return;
      name = n;
    }
    await perform(() async {
      final names = usernames
          .split(',')
          .map((x) => x.trim().toLowerCase())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();
      final people = await repo.db
          .from('pulse_profiles')
          .select('id,username')
          .inFilter('username', names);
      if (people.length != names.length) {
        notice('One or more usernames could not be found.');
        return;
      }
      final id = await repo.rpc('start_chat', {
        'p_users': people.map((p) => p['id']).toList(),
        'p_name': name,
        'p_group': group,
      });
      await repo.refresh();
      await repo.openChat(id as String);
      if (mounted) setState(() => section = 0);
    });
  }

  Future<void> send({bool file = false}) async {
    if (sending) return;
    if (!file && composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      String? attachment;
      var body = composer.text;
      if (file) {
        final result = await FilePicker.platform.pickFiles();
        if (result == null) return;
        final selected = result.files.single;
        if (selected.path == null) throw Exception('File unavailable');
        attachment = await repo.upload(File(selected.path!), selected.name);
        if (body.trim().isEmpty) body = selected.name;
      }
      await repo.send(body, reply: reply, attachment: attachment);
      composer.clear();
      reply = null;
      if (scroll.hasClients)
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
    } catch (_) {
      notice(
        'Could not send. Files require a connection and must be under 10 MB.',
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> messageAction(Map<String, dynamic> m, String action) async {
    final mine = m['sender_id'] == repo.uid;
    if (action == 'reply') {
      setState(() => reply = m['id']);
      return;
    }
    if (action == 'discard') {
      await repo.discardPending(m['id']);
      return;
    }
    await perform(() async {
      if (action == 'delete' && mine)
        await repo.rpc('change_message', {
          'p_id': m['id'],
          'p_body': '',
          'p_delete': true,
        });
      if (action == 'edit' && mine) {
        final value = await prompt(
          'Edit message',
          initial: m['body'],
          lines: 3,
        );
        if (value != null && value.isNotEmpty)
          await repo.rpc('change_message', {
            'p_id': m['id'],
            'p_body': value,
            'p_delete': false,
          });
      }
      if (action == 'hide' || action == 'star') {
        final prefs = repo.preferences.where((p) => p['message_id'] == m['id']);
        final starred = prefs.isNotEmpty && prefs.first['starred'] == true;
        await repo.rpc('message_pref', {
          'p_id': m['id'],
          'p_hidden': action == 'hide',
          'p_starred': action == 'star' ? !starred : starred,
        });
      }
      if (action.startsWith('react:'))
        await repo.rpc('react', {
          'p_id': m['id'],
          'p_emoji': action.substring(6),
        });
      if (action == 'forward') {
        final id = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Forward to'),
            children: repo.chats
                .map(
                  (chat) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, chat['id']),
                    child: Text(repo.chatName(chat)),
                  ),
                )
                .toList(),
          ),
        );
        if (id != null) {
          final previous = repo.activeChat;
          await repo.openChat(id);
          await repo.send('Forwarded: ${m['body']}');
          if (previous != null) await repo.openChat(previous);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final firstSetup = repo.me != null && repo.me!['username'] == null;
    final titles = [
      'Chats',
      'Calls',
      'Updates',
      'Communities',
      'Channels',
      'Settings',
    ];
    final icons = [
      Icons.chat_bubble_outline,
      Icons.call_outlined,
      Icons.auto_awesome_outlined,
      Icons.groups_outlined,
      Icons.campaign_outlined,
      Icons.settings_outlined,
    ];
    final body = firstSetup
        ? ProfilePanel(repo: repo, onSaved: repo.refresh)
        : section == 0
        ? chatsView(wide)
        : section == 1
        ? const FeatureNotice(
            icon: Icons.video_call_outlined,
            title: 'Calls are the next stage',
            text: 'Voice and video calls are not implemented in this beta. WebRTC signaling, TURN, incoming-call delivery and device testing are still required.',
          )
        : section == 2
        ? updatesView()
        : section == 3
        ? groupsView()
        : section == 4
        ? channelsView()
        : settingsView();
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: section,
                onDestinationSelected: (v) {
                  setState(() => section = v);
                },
                extended: false,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Icon(Icons.bolt_rounded, size: 36),
                ),
                destinations: List.generate(
                  6,
                  (i) => NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(titles[i]),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (repo.error != null)
                    MaterialBanner(
                      content: Text(repo.error!),
                      leading: const Icon(Icons.cloud_off),
                      actions: [
                        TextButton(
                          onPressed: repo.refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: section,
              onDestinationSelected: (v) {
                setState(() => section = v);
              },
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: List.generate(
                6,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: titles[i],
                ),
              ),
            ),
    );
  }

  Widget header(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null) action,
      ],
    ),
  );
  Widget chatsView(bool wide) {
    final list = Column(
      children: [
        header(
          'Pulse',
          action: IconButton(
            tooltip: 'New conversation',
            onPressed: () => newChat(),
            icon: const Icon(Icons.edit_square),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: search,
            onChanged: (_) {
              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: 'Search chats and loaded messages',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: repo.chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.forum_outlined, size: 60),
                      const SizedBox(height: 16),
                      const Text('Start your first conversation'),
                      TextButton(
                        onPressed: () => newChat(),
                        child: const Text('Find someone by username'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: repo.chats
                      .where(
                        (c) => repo
                            .chatName(c)
                            .toLowerCase()
                            .contains(search.text.toLowerCase()),
                      )
                      .map((c) {
                        final member = (c['pulse_members'] as List).where(
                          (m) => m['user_id'] != repo.uid,
                        );
                        final person = member.isEmpty
                            ? null
                            : repo.profiles[member.first['user_id']];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            selected: repo.activeChat == c['id'],
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            leading: PulseAvatar(
                              repo: repo,
                              path: person?['avatar_path'],
                              name: repo.chatName(c),
                            ),
                            title: Text(
                              repo.chatName(c),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              c['kind'] == 'group'
                                  ? 'Group conversation'
                                  : 'Tap to open conversation',
                            ),
                            onTap: () {
                              repo.openChat(c['id']);
                            },
                          ),
                        );
                      })
                      .toList(),
                ),
        ),
      ],
    );
    if (!wide && repo.activeChat != null) return chatView(mobile: true);
    if (!wide) return list;
    return Row(
      children: [
        SizedBox(width: 320, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: repo.activeChat == null
              ? const FeatureNotice(
                  icon: Icons.bolt_rounded,
                  title: 'Stay in your circle',
                  text: 'Choose a conversation or start a new one with a Pulse username.',
                )
              : chatView(),
        ),
      ],
    );
  }

  Widget chatView({bool mobile = false}) {
    final matches = repo.chats.where((c) => c['id'] == repo.activeChat);
    final chat = matches.isEmpty ? null : matches.first;
    final name = chat == null ? 'Conversation' : repo.chatName(chat);
    final filtered = repo.visibleMessages
        .where(
          (m) => m['body'].toString().toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
          child: Row(
            children: [
              if (mobile)
                IconButton(
                  onPressed: () {
                    setState(() {
                      repo.activeChat = null;
                      reply = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                      'Private beta · TLS protected · No E2EE yet',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh and mark as read',
                onPressed: () => perform(() async {
                  await repo.refresh();
                  await repo.markRead();
                }),
                icon: const Icon(Icons.done_all),
              ),
              if (chat?['kind'] == 'group')
                IconButton(
                  tooltip: 'Manage group member',
                  icon: const Icon(Icons.manage_accounts),
                  onPressed: () async {
                    final username = await prompt('Member username');
                    if (username == null || username.isEmpty) return;
                    if (!mounted) return;
                    final operation = await showDialog<String>(
                      context: context,
                      builder: (c) => SimpleDialog(
                        title: const Text('Group member action'),
                        children: ['add', 'remove', 'admin', 'member']
                            .map(
                              (a) => SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, a),
                                child: Text(a),
                              ),
                            )
                            .toList(),
                      ),
                    );
                    if (operation == null) return;
                    await perform(() async {
                      final p = await repo.db
                          .from('pulse_profiles')
                          .select('id')
                          .eq('username', username.toLowerCase())
                          .single();
                      await repo.rpc('manage_group', {
                        'p_chat': repo.activeChat,
                        'p_user': p['id'],
                        'p_action': operation,
                      });
                    });
                  },
                ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (chat == null) return;
                  final members = (chat['pulse_members'] as List).where(
                    (m) => m['user_id'] != repo.uid,
                  );
                  if (members.isEmpty) return;
                  final user = members.first['user_id'];
                  if (v == 'block')
                    await perform(() async {
                      await repo.rpc('block_user', {
                        'p_user': user,
                        'p_block': true,
                      });
                    });
                  if (v == 'report') {
                    final reason = await prompt(
                      'Report this account',
                      lines: 3,
                    );
                    if (reason != null && reason.isNotEmpty)
                      await perform(() async {
                        await repo.rpc('report_user', {
                          'p_user': user,
                          'p_reason': reason,
                        });
                      });
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('Block contact'),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report contact'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: repo.busy && filtered.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (c, i) => messageBubble(filtered[i]),
                ),
        ),
        if (reply != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.reply),
            title: const Text('Replying to a message'),
            trailing: IconButton(
              onPressed: () {
                setState(() => reply = null);
              },
              icon: const Icon(Icons.close),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach file, image or video (10 MB)',
                onPressed: sending ? null : () => send(file: true),
                icon: const Icon(Icons.add_circle_outline),
              ),
              Expanded(
                child: TextField(
                  controller: composer,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 8000,
                  decoration: const InputDecoration(
                    hintText: 'Write a message…',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: sending ? null : send,
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget messageBubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == repo.uid,
        deleted = m['deleted_at'] != null,
        pending = m['pending'] == true;
    final profile = repo.profiles[m['sender_id']];
    final read = repo.receipts.any(
      (r) => r['message_id'] == m['id'] && r['read_at'] != null,
    );
    final emojis = repo.reactions
        .where((r) => r['message_id'] == m['id'])
        .map((r) => r['emoji'])
        .join(' ');
    final star = repo.preferences.any(
      (p) => p['message_id'] == m['id'] && p['starred'] == true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            PulseAvatar(
              repo: repo,
              path: profile?['avatar_path'],
              name: profile?['display_name'] ?? 'P',
              radius: 15,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
              decoration: BoxDecoration(
                color: mine
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!mine)
                          Text(
                            profile?['display_name'] ?? 'Pulse user',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (m['reply_to'] != null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              '↩ Reply',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        Text(
                          deleted ? 'Message deleted' : m['body'],
                          style: TextStyle(
                            fontStyle: deleted
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        if (!deleted && m['attachment_path'] != null)
                          TextButton.icon(
                            onPressed: () => perform(() async {
                              final url = await repo.db.storage
                                  .from('pulse-media')
                                  .createSignedUrl(m['attachment_path'], 60);
                              if (!await launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              ))
                                throw Exception('Cannot open file');
                            }),
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Open attachment'),
                          ),
                        if (emojis.isNotEmpty) Text(emojis),
                        Text(
                          '${star ? '★ · ' : ''}${m['edited_at'] != null ? 'edited · ' : ''}${pending
                              ? (m['failure'] ?? 'Queued')
                              : mine
                              ? (read ? 'Read' : 'Sent')
                              : 'Received'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    onSelected: (v) => messageAction(m, v),
                    itemBuilder: (_) => pending
                        ? [
                            const PopupMenuItem(
                              value: 'discard',
                              child: Text('Discard queued message'),
                            ),
                          ]
                        : [
                            if (!deleted) ...[
                              const PopupMenuItem(
                                value: 'reply',
                                child: Text('Reply'),
                              ),
                              const PopupMenuItem(
                                value: 'forward',
                                child: Text('Forward'),
                              ),
                              const PopupMenuItem(
                                value: 'star',
                                child: Text('Star / unstar'),
                              ),
                              for (final emoji in [
                                '❤️',
                                '👍',
                                '😂',
                                '😮',
                                '😢',
                                '🙏',
                              ])
                                PopupMenuItem(
                                  value: 'react:$emoji',
                                  child: Text(emoji),
                                ),
                              if (mine) ...[
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete for everyone'),
                                ),
                              ],
                            ],
                            const PopupMenuItem(
                              value: 'hide',
                              child: Text('Delete for me'),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
          if (!mine) const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget updatesView() => Column(
    children: [
      header(
        'Updates',
        action: IconButton(
          tooltip: 'Post text status',
          onPressed: () async {
            final body = await prompt('Share a text status', lines: 4);
            if (body != null && body.isNotEmpty)
              await perform(() async {
                await repo.rpc('post_status', {'p_body': body});
              });
          },
          icon: const Icon(Icons.add),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Visible to people who share a chat with you. Expires after 24 hours.',
        ),
      ),
      Expanded(
        child: repo.statuses.isEmpty
            ? const Center(child: Text('No active status updates'))
            : ListView(
                children: repo.statuses
                    .map(
                      (s) => Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                repo.profiles[s['user_id']]?['display_name'] ??
                                    'Pulse user',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(s['body']),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
  Widget groupsView() => Column(
    children: [
      header(
        'Communities',
        action: IconButton(
          tooltip: 'Create a group',
          onPressed: () => newChat(group: true),
          icon: const Icon(Icons.group_add_outlined),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Group text chats work now. Communities that contain multiple groups, roles and invite links require the next stage.',
        ),
      ),
      Expanded(
        child: ListView(
          children: repo.chats
              .where((c) => c['kind'] == 'group')
              .map(
                (c) => ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(c['name']),
                  subtitle: Text(
                    '${(c['pulse_members'] as List).length} members',
                  ),
                  onTap: () {
                    repo.openChat(c['id']);
                    setState(() => section = 0);
                  },
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
  Widget channelsView() => Column(
    children: [
      header(
        'Channels',
        action: IconButton(
          tooltip: 'Create public channel',
          onPressed: () async {
            final name = await prompt('Public channel name');
            if (name == null || name.isEmpty) return;
            final description = await prompt('Channel description');
            if (description == null) return;
            await perform(() async {
              await repo.rpc('create_channel', {
                'p_name': name,
                'p_description': description,
              });
            });
          },
          icon: const Icon(Icons.add),
        ),
      ),
      Expanded(
        child: repo.channels.isEmpty
            ? const Center(child: Text('Create the first Pulse channel'))
            : ListView(
                children: repo.channels.map((c) {
                  final followed = repo.followers.any(
                    (f) =>
                        f['channel_id'] == c['id'] && f['user_id'] == repo.uid,
                  );
                  final count = repo.followers
                      .where((f) => f['channel_id'] == c['id'])
                      .length;
                  final items = repo.posts
                      .where((p) => p['channel_id'] == c['id'])
                      .toList();
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${c['name']}${c['verified'] == true ? ' ✓' : ''}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton(
                                onPressed: () => perform(() async {
                                  await repo.rpc('follow_channel', {
                                    'p_channel': c['id'],
                                    'p_follow': !followed,
                                  });
                                }),
                                child: Text(followed ? 'Unfollow' : 'Follow'),
                              ),
                            ],
                          ),
                          Text('$count followers · ${c['description']}'),
                          if (c['owner_id'] == repo.uid)
                            TextButton.icon(
                              onPressed: () async {
                                final body = await prompt(
                                  'Channel announcement',
                                  lines: 4,
                                );
                                if (body != null && body.isNotEmpty)
                                  await perform(() async {
                                    await repo.rpc('channel_post', {
                                      'p_channel': c['id'],
                                      'p_body': body,
                                    });
                                  });
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text('Post announcement'),
                            ),
                          for (final p in items.take(5))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(p['body']),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      ),
    ],
  );
  Widget settingsView() => ListView(
    children: [
      header('Settings'),
      FutureBuilder<dynamic>(
        future: repo.rpc('is_admin', {}),
        builder: (_, snapshot) => snapshot.data == true
            ? ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Administrator dashboard'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminScreen(repo: repo)),
                ),
              )
            : const SizedBox.shrink(),
      ),
      if (repo.me != null)
        ListTile(
          leading: PulseAvatar(
            repo: repo,
            path: repo.me!['avatar_path'],
            name: repo.me!['display_name'],
          ),
          title: Text(repo.me!['display_name']),
          subtitle: Text('@${repo.me!['username'] ?? 'choose_username'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Your profile')),
                body: ProfilePanel(
                  repo: repo,
                  onSaved: () async {
                    await repo.refresh();
                    if (mounted) Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.dark_mode_outlined),
        title: const Text('Dark / light theme'),
        onTap: widget.toggleTheme,
      ),
      Card(
        margin: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pulse Premium · \$3 / month',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                repo.premiumUntil != null &&
                        repo.premiumUntil!.isAfter(DateTime.now())
                    ? 'Premium active until ${repo.premiumUntil!.toLocal().toString().substring(0, 10)}'
                    : 'Subscription billing is not connected yet. Promo redemption is available.',
              ),
              const SizedBox(height: 8),
              const Text(
                'This beta records Premium access. Exclusive themes, animated avatars, larger uploads and other benefits are not unlocked yet.',
              ),
              TextButton(
                onPressed: () async {
                  final code = await prompt('Redeem Premium code');
                  if (code != null && code.isNotEmpty)
                    await perform(() async {
                      await repo.rpc('redeem', {'p_code': code});
                      notice('Premium redeemed successfully.');
                    });
                },
                child: const Text('Redeem a code'),
              ),
            ],
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Change password'),
        onTap: () async {
          final password = await prompt('New password (12+ characters)');
          if (password != null && password.length >= 12)
            await perform(() async {
              await repo.db.auth.updateUser(UserAttributes(password: password));
              notice('Password updated');
            });
        },
      ),
      ListTile(
        leading: const Icon(Icons.block),
        title: const Text('Blocked accounts'),
        subtitle: Text('${repo.blocks.length} blocked'),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const Text('Blocked accounts'),
              children: repo.blocks
                  .map(
                    (b) => SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(c);
                        perform(() async {
                          await repo.rpc('block_user', {
                            'p_user': b['blocked_id'],
                            'p_block': false,
                          });
                        });
                      },
                      child: Text(
                        'Unblock ${repo.profiles[b['blocked_id']]?['display_name'] ?? b['blocked_id']}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign out this device'),
        onTap: () => perform(() => repo.signOut()),
      ),
      ListTile(
        leading: const Icon(Icons.devices),
        title: const Text('Sign out all devices'),
        subtitle: const Text(
          'Revokes refresh sessions; existing access tokens expire normally.',
        ),
        onTap: () => perform(() => repo.signOut(all: true)),
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Pulse 0.1.0 · Private beta\nMessages are protected by access policies and TLS. End-to-end encryption, individual device management and MFA UI are not implemented yet. Do not use this beta for sensitive conversations.',
        ),
      ),
    ],
  );
}

class FeatureNotice extends StatelessWidget {
  const FeatureNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class PulseAvatar extends StatefulWidget {
  const PulseAvatar({
    super.key,
    required this.repo,
    required this.path,
    required this.name,
    this.radius = 24,
  });
  final PulseRepository repo;
  final String? path;
  final String name;
  final double radius;
  @override
  State<PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<PulseAvatar> {
  Future<String?>? future;
  @override
  void initState() {
    super.initState();
    future = widget.repo.avatar(widget.path);
  }

  @override
  void didUpdateWidget(PulseAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) future = widget.repo.avatar(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: future,
    builder: (_, s) => CircleAvatar(
      radius: widget.radius,
      backgroundImage: s.data == null ? null : NetworkImage(s.data!),
      child: s.data != null
          ? null
          : Text(
              widget.name.isEmpty
                  ? 'P'
                  : widget.name.characters.first.toUpperCase(),
            ),
    ),
  );
}
