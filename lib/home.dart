import 'contact_picker.dart';
import 'brand.dart';
import 'appearance.dart';
import 'appearance_settings.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart' hide Row;
import 'profile.dart';
import 'avatar.dart';
import 'admin.dart';
import 'channels.dart';
import 'notifications.dart';
import 'push.dart';
import 'statuses.dart';
import 'calls.dart';
import 'media.dart';
import 'voice.dart';
import 'social.dart';
import 'social_repository.dart';
import 'social_create.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.toggleTheme});
  final VoidCallback toggleTheme;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PulseRepository repo;
  late final PulseCalls calls;
  bool openingCall = false;
  int section = 0, socialSection = 0;
  late final SocialStore social;
  final composer = TextEditingController(), search = TextEditingController();
  String? reply;
  bool sending = false;
  int seenIncoming = 0;
  OverlayEntry? messageToast;
  Timer? toastTimer;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    repo = PulseRepository(Supabase.instance.client)..addListener(changed);
    repo.initialize();
    social = SocialStore(repo);
    calls = PulseCalls(repo)..addListener(changed);
    calls.start();
  }

  void changed() {
    if (mounted) {
      setState(() {});
      if (repo.incomingSerial != seenIncoming && repo.incoming != null) {
        seenIncoming = repo.incomingSerial;
        showIncoming(repo.incoming!);
      }
    }
  }

  void showIncoming(Map<String, dynamic> message) {
    if (repo.activeChat == message['chat_id'] &&
        socialSection == 3 &&
        section == 0) {
      repo.markRead();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      messageToast?.remove();
      toastTimer?.cancel();
      final sender = repo.profiles[message['sender_id']];
      messageToast = OverlayEntry(
        builder: (c) => Positioned(
          top: MediaQuery.paddingOf(c).top + 12,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(c).colorScheme.surfaceContainerHigh,
                child: ListTile(
                  leading: PulseAvatar(
                    repo: repo,
                    path: sender?['avatar_path'],
                    name: sender?['display_name'] ?? 'Pulse',
                  ),
                  title: Text(
                    sender?['display_name'] ?? 'New Pulse message',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    message['body']?.toString().isNotEmpty == true
                        ? message['body']
                        : 'Sent an attachment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      messageToast?.remove();
                      messageToast = null;
                    },
                  ),
                  onTap: () async {
                    messageToast?.remove();
                    messageToast = null;
                    await repo.openChat(message['chat_id']);
                    if (mounted)
                      setState(() {
                        socialSection = 3;
                        section = 0;
                      });
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(messageToast!);
      toastTimer = Timer(const Duration(seconds: 5), () {
        messageToast?.remove();
        messageToast = null;
      });
    });
  }

  @override
  void dispose() {
    toastTimer?.cancel();
    messageToast?.remove();
    calls.removeListener(changed);
    calls.dispose();
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
    final usernames = group
        ? await prompt('Group members (usernames separated by commas)')
        : await pickPulseContact(context, repo);
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
      if (mounted)
        setState(() {
          section = 0;
          socialSection = 3;
        });
    });
  }

  Future<void> send({bool file = false}) async {
    if (sending) return;
    if (!file && composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      String? attachment, mime;
      final chatId = repo.activeChat;
      final replying = reply;
      var body = composer.text;
      if (file) {
        final result = await FilePicker.pickFile();
        if (result == null) return;
        final selected = result;
        if (selected.path == null) throw Exception('File unavailable');
        mime = mimeFor(selected.name);
        attachment = await repo.upload(
          File(selected.path!),
          selected.name,
          contentType: mime,
          chatId: chatId,
        );
        if (body.trim().isEmpty) body = selected.name;
      }
      await repo.send(
        body,
        reply: replying,
        attachment: attachment,
        chatId: chatId,
        mediaKind: mime == null ? null : kindFor(mime),
        mediaMime: mime,
      );
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

  Future<void> recordVoice() async {
    final chatId = repo.activeChat;
    if (sending || chatId == null) return;
    final replying = reply;
    await PulseMedia.pauseAll();
    if (!mounted) return;
    final note = await showDialog<PulseVoiceNote>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceRecorderDialog(),
    );
    if (note == null) return;
    try {
      if (!mounted) return;
      setState(() => sending = true);
      final path = await repo.upload(
        note.file,
        'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        chatId: chatId,
      );
      await repo.send(
        '',
        reply: replying,
        attachment: path,
        chatId: chatId,
        mediaKind: 'audio',
        mediaMime: 'audio/mp4',
        duration: note.durationMs,
        waveform: note.waveform,
      );
      reply = null;
    } catch (_) {
      notice(
        'Could not upload voice note. Check your connection and try again.',
      );
    } finally {
      try {
        if (await note.file.exists()) await note.file.delete();
      } catch (_) {}
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> startCall(String kind) async {
    if (openingCall || repo.activeChat == null) return;
    await PulseMedia.pauseAll();
    openingCall = true;
    try {
      final credentials = await calls.invoke(
        'start',
        chatId: repo.activeChat,
        kind: kind,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PulseCallScreen(calls: calls, credentials: credentials),
        ),
      );
    } catch (error) {
      notice(callError(error));
    } finally {
      openingCall = false;
      await calls.refresh();
    }
  }

  Future<void> openCall(Map<String, dynamic> call) async {
    if (openingCall) return;
    await PulseMedia.pauseAll();
    openingCall = true;
    try {
      final action = calls.ownMember(call)?['state'] == 'ringing'
          ? 'accept'
          : 'join';
      final credentials = await calls.invoke(action, callId: call['id']);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PulseCallScreen(calls: calls, credentials: credentials),
        ),
      );
    } catch (error) {
      notice(callError(error));
    } finally {
      openingCall = false;
      await calls.refresh();
    }
  }

  Widget incomingCallBanner(Map<String, dynamic> call) => MaterialBanner(
    content: Text(
      '${repo.profiles[call['caller_id']]?['display_name'] ?? 'Someone'} is calling · ${call['kind']}',
    ),
    leading: const Icon(Icons.ring_volume),
    actions: [
      TextButton(
        onPressed: () async {
          try {
            await calls.decline(call['id']);
          } catch (e) {
            notice(callError(e));
          }
        },
        child: const Text('Decline'),
      ),
      FilledButton(
        onPressed: () => openCall(call),
        child: const Text('Accept'),
      ),
    ],
  );

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    if (message['pending'] == true) {
      await messageAction(message, 'discard');
      return;
    }
    final mine = message['sender_id'] == repo.uid;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Choose who this message is removed for.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'hide'),
            child: const Text('Delete for me'),
          ),
          if (mine && message['deleted_at'] == null)
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'delete'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice != null) await messageAction(message, choice);
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
      'Home',
      'Reels',
      'Create',
      'Chats',
      'Communities',
      'Profile',
    ];
    final icons = [
      Icons.home_outlined,
      Icons.play_circle_outline,
      Icons.add_box_outlined,
      Icons.chat_bubble_outline,
      Icons.groups_outlined,
      Icons.person_outline,
    ];
    final messenger = section == 0
        ? chatsView(wide)
        : section == 1
        ? CallsList(calls: calls, open: openCall)
        : section == 2
        ? updatesView()
        : channelsView();
    final body = repo.me == null
        ? Center(
            child: repo.error == null
                ? const PulseLoader()
                : TextButton(
                    onPressed: repo.refresh,
                    child: const Text('Reconnect to load your account'),
                  ),
          )
        : firstSetup
        ? ProfilePanel(repo: repo, onSaved: repo.refresh)
        : socialSection == 0
        ? SocialFeed(store: social)
        : socialSection == 1
        ? PulseReels(store: social)
        : socialSection == 3
        ? Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: ChoiceChip(
                          label: Text(
                            ['Chats', 'Calls', 'Updates', 'Channels'][i],
                          ),
                          selected: section == i,
                          onSelected: (_) => setState(() => section = i),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: openSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(child: messenger),
            ],
          )
        : socialSection == 4
        ? groupsView()
        : SocialProfile(store: social, user: repo.uid, settings: openSettings);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: socialSection,
                onDestinationSelected: (v) {
                  selectSocial(v);
                },
                extended: MediaQuery.sizeOf(context).width >= 1100,
                labelType: NavigationRailLabelType.none,
                groupAlignment: -.8,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: PulseMark(size: 40, tile: true),
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
                  if (calls.incoming != null)
                    incomingCallBanner(calls.incoming!),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : PulseBottomNav(
              selected: socialSection,
              onSelect: selectSocial,
              unread: repo.unread.values.fold(0, (a, b) => a + b),
            ),
    );
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('PULSE settings')),
          body: settingsView(),
        ),
      ),
    );
  }

  Future<void> selectSocial(int value) async {
    await PulseMedia.pauseAll();
    if (!mounted) return;
    if (repo.me == null || repo.me!['username'] == null) return;
    if (value == 2) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => SocialComposer(store: social)),
      );
      if (saved == true && mounted) setState(() => socialSection = 5);
      return;
    }
    setState(() => socialSection = value);
  }

  Widget header(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
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
          'Chats',
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
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            leading: PulseAvatar(
                              repo: repo,
                              path: person?['avatar_path'],
                              name: repo.chatName(c),
                            ),
                            trailing: (repo.unread[c['id']] ?? 0) > 0
                                ? Badge(label: Text('${repo.unread[c['id']]}'))
                                : null,
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
                  text:
                      'Choose a conversation or start a new one with a Pulse username.',
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
                tooltip: 'Voice call',
                onPressed:
                    repo.requestFor(repo.activeChat) == null ||
                        repo.requestFor(repo.activeChat)?['state'] == 'accepted'
                    ? () => startCall('voice')
                    : null,
                icon: const Icon(Icons.call_outlined),
              ),
              IconButton(
                tooltip: 'Video call',
                onPressed:
                    repo.requestFor(repo.activeChat) == null ||
                        repo.requestFor(repo.activeChat)?['state'] == 'accepted'
                    ? () => startCall('video')
                    : null,
                icon: const Icon(Icons.videocam_outlined),
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
          child: PulseWallpaper(
            child: repo.busy && filtered.isEmpty
                ? const Center(child: PulseLoader())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (c, i) => messageBubble(filtered[i]),
                  ),
          ),
        ),
        if (repo.requestFor(repo.activeChat) != null &&
            repo.requestFor(repo.activeChat)!['state'] != 'accepted')
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: ListTile(
              title: Text(
                repo.requestFor(repo.activeChat)!['state'] == 'declined'
                    ? 'Message request declined'
                    : repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid
                    ? 'Message request'
                    : 'Waiting for acceptance',
              ),
              subtitle: Text(
                repo.requestFor(repo.activeChat)!['state'] == 'declined'
                    ? 'Messaging is unavailable for this request.'
                    : repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid
                    ? 'Accept before replying. You can also decline or block.'
                    : 'You can send messages; they can reply after accepting.',
              ),
              trailing:
                  repo.requestFor(repo.activeChat)!['recipient_id'] ==
                          repo.uid &&
                      repo.requestFor(repo.activeChat)!['state'] == 'pending'
                  ? Wrap(
                      children: [
                        TextButton(
                          onPressed: () => perform(
                            () => repo.rpc('respond_request', {
                              'p_chat': repo.activeChat,
                              'p_accept': false,
                            }),
                          ),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: () => perform(
                            () => repo.rpc('respond_request', {
                              'p_chat': repo.activeChat,
                              'p_accept': true,
                            }),
                          ),
                          child: const Text('Accept'),
                        ),
                      ],
                    )
                  : null,
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
        IgnorePointer(
          ignoring: !repo.canReply(repo.activeChat),
          child: Opacity(
            opacity: repo.canReply(repo.activeChat) ? 1 : .4,
            child: Padding(
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
                  IconButton(
                    tooltip: 'Record voice note',
                    onPressed: sending ? null : recordVoice,
                    icon: const Icon(Icons.mic_none),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: sending ? null : send,
                    child: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: PulseLoader(size: 22),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
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
                        if (!deleted &&
                            RegExp(
                              r'pulse:post:([0-9a-f-]{36})',
                            ).hasMatch(m['body'] as String))
                          TextButton.icon(
                            onPressed: () => openSocialPost(
                              context,
                              social,
                              RegExp(
                                r'pulse:post:([0-9a-f-]{36})',
                              ).firstMatch(m['body'])!.group(1)!,
                            ),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('Open Pulse post'),
                          ),
                        if (!deleted && m['attachment_path'] != null)
                          PulseAttachment(
                            key: ValueKey(m['id']),
                            repo: repo,
                            message: m,
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                              if ((m['body'] as String? ?? '').isNotEmpty)
                                PopupMenuItem(
                                  value: 'forward',
                                  child: Text(
                                    m['attachment_path'] == null
                                        ? 'Forward'
                                        : 'Forward text only',
                                  ),
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

  Widget updatesView() => StatusUpdates(repo: repo);
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
                    setState(() {
                      section = 0;
                      socialSection = 3;
                    });
                  },
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
  Widget channelsView() => ChannelsScreen(repo: repo);
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
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Themes & wallpapers'),
        subtitle: const Text('Wallpapers, matching colors, splash and loading'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PulseAppearancePage()),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.dark_mode_outlined),
        title: const Text('Dark / light theme'),
        onTap: widget.toggleTheme,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Message notifications'),
        subtitle: Text(
          PulsePush.instance.status ??
              'Alerts while Pulse is running. Windows closed-app push is not configured.',
        ),
        value: PulseNotifications.instance.enabled,
        onChanged: (value) async {
          await perform(() => PulseNotifications.instance.setEnabled(value));
        },
      ),
      ListTile(
        leading: const Icon(Icons.notification_add_outlined),
        title: const Text('Test notification'),
        onTap: () async {
          final ok = await PulseNotifications.instance.test();
          notice(
            ok
                ? 'Notification requested. Check your device alerts.'
                : 'Notifications are disabled or unavailable. Check system permissions.',
          );
        },
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
                          social.hiddenCreators.remove(b['blocked_id']);
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
          'PULSE 0.4.4 · Private beta\nMessages are protected by access policies and TLS. End-to-end encryption, individual device management and MFA UI are not implemented yet. Do not use this beta for sensitive conversations.',
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
