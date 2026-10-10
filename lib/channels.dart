import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'profile.dart';
import 'repository.dart' hide Row;

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final name = await channelPrompt(context, 'Channel name', max: 80);
    if (name == null) return;
    try {
      await widget.repo.rpc('create_channel', {
        'p_name': name,
        'p_description': '',
      });
      await widget.repo.refresh();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.repo.channels
        .where(
          (c) => '${c['name']} ${c['description']}'.toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xff008b82), Color(0xff604bc2)],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 36),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your world, on Pulse',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Follow channels. Catch the moment live.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: create,
                tooltip: 'Create channel',
                icon: const Icon(Icons.add_circle, color: Colors.white),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Discover channels',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('No channels found'))
              : ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (_, i) {
                    final c = channels[i];
                    final followed = widget.repo.followers.any(
                      (f) =>
                          f['channel_id'] == c['id'] &&
                          f['user_id'] == widget.repo.uid,
                    );
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: PulseAvatar(
                          repo: widget.repo,
                          path: c['avatar_path'],
                          name: c['name'],
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                c['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (c['verified'] == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.verified,
                                  size: 18,
                                  color: Color(0xff00bfa6),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${widget.repo.followers.where((f) => f['channel_id'] == c['id']).length} followers · ${c['description']}',
                        ),
                        trailing: Icon(
                          followed ? Icons.check_circle : Icons.chevron_right,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChannelDetail(
                              repo: widget.repo,
                              channelId: c['id'],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<String?> channelPrompt(
  BuildContext context,
  String title, {
  int max = 500,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, maxLength: max, maxLines: 3),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty)
              Navigator.pop(c, controller.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

void channelError(BuildContext context, Object error) {
  final text = error is PostgrestException
      ? error.message
      : error is FunctionException
      ? 'Live service unavailable. Check LiveKit configuration and your connection.'
      : 'Unable to complete this action. Please try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class ChannelDetail extends StatefulWidget {
  const ChannelDetail({super.key, required this.repo, required this.channelId});
  final PulseRepository repo;
  final String channelId;
  @override
  State<ChannelDetail> createState() => _ChannelDetailState();
}

class _ChannelDetailState extends State<ChannelDetail> {
  Map<String, dynamic>? channel, live;
  List<Map<String, dynamic>> posts = [], reactions = [];
  bool admin = false, followed = false, loading = true, busy = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    busy = true;
    try {
      final db = widget.repo.db;
      final c = await db
          .from('pulse_channels')
          .select()
          .eq('id', widget.channelId)
          .single();
      final a = await widget.repo.rpc('channel_admin', {
        'p_channel': widget.channelId,
      });
      final f = await db
          .from('pulse_followers')
          .select()
          .eq('channel_id', widget.channelId)
          .eq('user_id', widget.repo.uid)
          .maybeSingle();
      final p = await db
          .from('pulse_posts')
          .select()
          .eq('channel_id', widget.channelId)
          .order('created_at', ascending: false)
          .limit(100);
      final ids = p.map((row) => row['id'] as String).toList();
      final r = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await db
                .from('pulse_post_reactions')
                .select()
                .inFilter('post_id', ids);
      final l = await db
          .from('pulse_live_sessions')
          .select()
          .eq('channel_id', widget.channelId)
          .eq('status', 'live')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);
      if (mounted)
        setState(() {
          channel = c;
          admin = a == true;
          followed = f != null;
          posts = p;
          reactions = r;
          live = l.isEmpty ? null : l.first;
          loading = false;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Could not load channel. Check your connection.';
        });
    } finally {
      busy = false;
    }
  }

  Future<void> action(Future<void> Function() run) async {
    try {
      await run();
      await load();
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  Future<void> edit() async {
    final name = await channelPrompt(
      context,
      'Channel name',
      max: 80,
      initial: channel!['name'],
    );
    if (name == null || !mounted) return;
    final description = await channelPrompt(
      context,
      'Description',
      initial: channel!['description'],
    );
    if (description == null) return;
    await action(() async {
      await widget.repo.rpc('channel_update', {
        'p_channel': widget.channelId,
        'p_name': name,
        'p_description': description,
        'p_avatar': channel!['avatar_path'],
      });
    });
  }

  Future<void> photo() async {
    await action(() async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (file?.path == null) return;
      final path = await widget.repo.upload(
        File(file!.path!),
        file.name,
        avatar: true,
      );
      await widget.repo.rpc('channel_update', {
        'p_channel': widget.channelId,
        'p_name': channel!['name'],
        'p_description': channel!['description'],
        'p_avatar': path,
      });
    });
  }

  Future<void> promote() async {
    final username = await channelPrompt(
      context,
      'Administrator username',
      max: 24,
    );
    if (username == null) return;
    await action(() async {
      final user = await widget.repo.db
          .from('pulse_profiles')
          .select('id')
          .eq('username', username.toLowerCase().replaceFirst('@', ''))
          .single();
      await widget.repo.rpc('channel_set_admin', {
        'p_channel': widget.channelId,
        'p_user': user['id'],
        'p_enabled': true,
      });
    });
  }

  Future<void> goLive() async {
    final title = await channelPrompt(context, 'Livestream title', max: 100);
    if (title == null) return;
    try {
      final response = await widget.repo.db.functions.invoke(
        'pulse-live',
        body: {
          'action': 'start',
          'channel_id': widget.channelId,
          'title': title,
        },
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveScreen(
            repo: widget.repo,
            sessionId: response.data['session_id'],
            initial: Map<String, dynamic>.from(response.data),
            host: true,
          ),
        ),
      );
      await load();
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(channel?['name'] ?? 'Channel'),
      actions: [
        if (admin)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') edit();
              if (value == 'photo') photo();
              if (value == 'admin') promote();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit channel')),
              const PopupMenuItem(
                value: 'photo',
                child: Text('Change channel photo'),
              ),
              if (channel?['owner_id'] == widget.repo.uid)
                const PopupMenuItem(
                  value: 'admin',
                  child: Text('Add administrator'),
                ),
            ],
          ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : channel == null
        ? Center(
            child: TextButton(onPressed: load, child: Text(error ?? 'Retry')),
          )
        : Column(
            children: [
              if (error != null) Text(error!),
              ListTile(
                leading: PulseAvatar(
                  repo: widget.repo,
                  path: channel!['avatar_path'],
                  name: channel!['name'],
                ),
                title: Text(channel!['name']),
                subtitle: Text(channel!['description']),
                trailing: FilledButton.tonal(
                  onPressed: () => action(() async {
                    await widget.repo.rpc('follow_channel', {
                      'p_channel': widget.channelId,
                      'p_follow': !followed,
                    });
                    await widget.repo.refresh();
                  }),
                  child: Text(followed ? 'Following' : 'Follow'),
                ),
              ),
              if (live != null)
                ListTile(
                  tileColor: Theme.of(context).colorScheme.tertiaryContainer,
                  leading: const Icon(Icons.live_tv, color: Colors.redAccent),
                  title: Text('LIVE · ${live!['title']}'),
                  trailing: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveScreen(
                          repo: widget.repo,
                          sessionId: live!['id'],
                          host: live!['host_id'] == widget.repo.uid,
                        ),
                      ),
                    ),
                    child: const Text('Watch'),
                  ),
                ),
              if (admin && live == null)
                TextButton.icon(
                  onPressed: goLive,
                  icon: const Icon(Icons.videocam),
                  label: const Text('Go live'),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final post = posts[i];
                      final all = reactions
                          .where((r) => r['post_id'] == post['id'])
                          .toList();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post['body'],
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${post['created_at']}'.substring(0, 16),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              Wrap(
                                children: ['❤️', '🔥', '👏', '👍', '🎉'].map((
                                  emoji,
                                ) {
                                  final own = all.any(
                                    (r) =>
                                        r['user_id'] == widget.repo.uid &&
                                        r['emoji'] == emoji,
                                  );
                                  return TextButton(
                                    onPressed: () => action(() async {
                                      await widget.repo.rpc('post_react', {
                                        'p_post': post['id'],
                                        'p_emoji': own ? null : emoji,
                                      });
                                    }),
                                    child: Text(
                                      '$emoji ${all.where((r) => r['emoji'] == emoji).length}',
                                      style: TextStyle(
                                        fontWeight: own
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (admin)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final body = await channelPrompt(
                        context,
                        'Post an announcement',
                        max: 8000,
                      );
                      if (body != null)
                        await action(() async {
                          await widget.repo.rpc('channel_post', {
                            'p_channel': widget.channelId,
                            'p_body': body,
                          });
                        });
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Post announcement'),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Only administrators can post. Join live broadcasts to chat.',
                  ),
                ),
            ],
          ),
  );
}

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.repo,
    required this.sessionId,
    required this.host,
    this.initial,
  });
  final PulseRepository repo;
  final String sessionId;
  final bool host;
  final Map<String, dynamic>? initial;
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  final composer = TextEditingController();
  List<Map<String, dynamic>> chat = [];
  Timer? timer;
  bool connected = false,
      muted = false,
      sending = false,
      ending = false,
      polling = false;
  String? error;
  @override
  void initState() {
    super.initState();
    room.addListener(changed);
    connect();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> connect() async {
    try {
      final data =
          widget.initial ??
          Map<String, dynamic>.from(
            (await widget.repo.db.functions.invoke(
              'pulse-live',
              body: {'action': 'join', 'session_id': widget.sessionId},
            )).data,
          );
      await room.connect(data['url'], data['token']);
      if (widget.host) {
        await room.localParticipant?.setCameraEnabled(true);
        await room.localParticipant?.setMicrophoneEnabled(true);
      }
      if (!mounted) {
        await room.disconnect();
        return;
      }
      setState(() {
        connected = true;
        error = null;
      });
      timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
      await poll();
    } catch (_) {
      if (widget.host) {
        try {
          await widget.repo.db.functions.invoke(
            'pulse-live',
            body: {'action': 'end', 'session_id': widget.sessionId},
          );
        } catch (_) {
          /* lease expires if unavailable */
        }
      }
      await room.disconnect();
      if (mounted)
        setState(
          () => error = 'Could not connect. LiveKit must be configured. Hosts also need camera and microphone permission.',
        );
    }
  }

  Future<void> poll() async {
    if (polling || ending) return;
    polling = true;
    try {
      if (widget.host && connected)
        await widget.repo.rpc('live_touch', {'p_session': widget.sessionId});
      final session = await widget.repo.db
          .from('pulse_live_sessions')
          .select()
          .eq('id', widget.sessionId)
          .single();
      if (session['status'] != 'live' ||
          DateTime.parse(session['expires_at'])
              .isBefore(DateTime.now().toUtc())) {
        timer?.cancel();
        await room.disconnect();
        if (mounted)
          setState(() {
            connected = false;
            error = 'This livestream has ended.';
          });
        return;
      }
      final rows = await widget.repo.db
          .from('pulse_live_chat')
          .select('*,pulse_profiles(display_name)')
          .eq('session_id', widget.sessionId)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() => chat = rows.reversed.toList());
    } catch (_) {
      if (mounted) setState(() => error = 'Live chat is reconnecting…');
    } finally {
      polling = false;
    }
  }

  Future<void> end() async {
    if (ending) return;
    setState(() => ending = true);
    try {
      if (widget.host)
        await widget.repo.db.functions.invoke(
          'pulse-live',
          body: {'action': 'end', 'session_id': widget.sessionId},
        );
      await room.disconnect();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => ending = false);
        channelError(context, e);
      }
    }
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await widget.repo.rpc('live_chat_send', {
        'p_session': widget.sessionId,
        'p_id': const Uuid().v4(),
        'p_body': composer.text.trim(),
      });
      composer.clear();
      await poll();
    } catch (e) {
      if (mounted) channelError(context, e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    room.removeListener(changed);
    unawaited(room.dispose());
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    lk.VideoTrack? track;
    if (widget.host) {
      for (final publication
          in room.localParticipant?.videoTrackPublications ?? []) {
        if (publication.track is lk.VideoTrack) {
          track = publication.track as lk.VideoTrack;
          break;
        }
      }
    } else {
      for (final participant in room.remoteParticipants.values) {
        for (final publication in participant.videoTrackPublications) {
          if (publication.track is lk.VideoTrack) {
            track = publication.track as lk.VideoTrack;
            break;
          }
        }
        if (track != null) break;
      }
    }
    return PopScope(
      canPop: !widget.host || !connected,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) end();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.host ? 'Broadcasting live' : 'Channel live'),
          actions: [
            TextButton(
              onPressed: ending ? null : end,
              child: Text(widget.host ? 'End live' : 'Leave'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: track == null
                    ? Center(
                        child: Text(
                          error ??
                              (connected
                                  ? 'Waiting for host video…'
                                  : 'Connecting…'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : lk.VideoTrackRenderer(track),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${room.connectionState.name} · ${room.remoteParticipants.length} other connected participants',
              ),
            ),
            if (error != null && track != null) Text(error!),
            if (widget.host && connected)
              IconButton(
                onPressed: () async {
                  try {
                    await room.localParticipant?.setMicrophoneEnabled(muted);
                    if (mounted) setState(() => muted = !muted);
                  } catch (e) {
                    if (mounted) channelError(context, e);
                  }
                },
                icon: Icon(muted ? Icons.mic_off : Icons.mic),
              ),
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: chat.length,
                itemBuilder: (_, i) {
                  final m = chat[i];
                  return ListTile(
                    dense: true,
                    title: Text(m['body']),
                    subtitle: Text(
                      m['pulse_profiles']?['display_name'] ?? 'Pulse fan',
                    ),
                    trailing: widget.host
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await widget.repo.rpc('live_chat_hide', {
                                  'p_message': m['id'],
                                });
                                await poll();
                              } catch (e) {
                                if (mounted) channelError(context, e);
                              }
                            },
                          )
                        : null,
                  );
                },
              ),
            ),
            if (connected)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: composer,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            hintText: 'Chat with the channel · followers only',
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
              ),
          ],
        ),
      ),
    );
  }
}
