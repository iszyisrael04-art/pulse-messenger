import 'live_party.dart';
import 'channel_composer.dart';
import 'channel_media.dart';
import 'media.dart';
import 'channel_updates.dart';
import 'text_prompt.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'avatar.dart';
import 'repository.dart' hide Row;

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.repo, this.updates});
  final PulseRepository repo;
  final PulseChannelUpdates? updates;
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((widget.updates?.counts[c['id']] ?? 0) > 0)
                              Badge(
                                label: Text(
                                  (widget.updates!.counts[c['id']] ?? 0) > 99
                                      ? '99+'
                                      : '${widget.updates!.counts[c['id']]}',
                                ),
                                child: const Icon(Icons.campaign_outlined),
                              ),
                            const SizedBox(width: 8),
                            Icon(
                              followed ? Icons.check_circle : Icons.chevron_right,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${widget.repo.followers.where((f) => f['channel_id'] == c['id']).length} followers · ${c['description']}',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChannelDetail(
                              repo: widget.repo,
                              channelId: c['id'],
                              updates: widget.updates,
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
}) => showPulseTextPrompt(context, title, initial: initial, maxLength: max);

String liveErrorMessage(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is FunctionException) {
    if (error.status == 503) {
      return 'Live broadcasting is not ready yet. Please try again later.';
    }
    if (error.status == 401) return 'Your session expired. Sign in again.';
    final details = error.details;
    if (details is Map && details['error'] is String)
      return details['error'] as String;
    return 'The live service returned error ${error.status}. Please retry.';
  }
  return 'Could not connect to the live server. Check your network and camera/microphone permissions.';
}

void channelError(BuildContext context, Object error) {
  final message = error is FunctionException || error is PostgrestException
      ? liveErrorMessage(error)
      : error is StorageException
      ? 'Picture upload failed. Choose a JPG, PNG or WebP 15 MB or smaller.'
      : 'Unable to complete this action. Check your connection and try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class ChannelDetail extends StatefulWidget {
  const ChannelDetail({
    super.key,
    required this.repo,
    required this.channelId,
    this.updates,
  });
  final PulseRepository repo;
  final PulseChannelUpdates? updates;
  final String channelId;
  @override
  State<ChannelDetail> createState() => _ChannelDetailState();
}

class _ChannelDetailState extends State<ChannelDetail> {
  Map<String, dynamic>? channel, live;
  List<Map<String, dynamic>> posts = [], reactions = [];
  bool admin = false, followed = false, loading = true, busy = false;
  final announcement = TextEditingController();
  String postQuery = '';
  bool mediaOnly = false, hasMore = true, reloadRequested = false;
  final historyScroll = ScrollController();
  bool sendingAnnouncement = false;
  String? error;
  Timer? timer;
  ModalRoute<dynamic>? visibilityRoute;
  String? previousChannel;
  bool Function()? previousVisible;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visibilityRoute = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    previousChannel = widget.updates?.activeChannel;
    previousVisible = widget.updates?.activeChannelVisible;
    widget.updates?.activeChannel = widget.channelId;
    widget.updates?.activeChannelVisible = () =>
        mounted &&
        visibilityRoute?.isCurrent == true &&
        postQuery.isEmpty &&
        !mediaOnly &&
        (!historyScroll.hasClients || historyScroll.offset < 100);
    historyScroll.addListener(() {
      if (historyScroll.hasClients && historyScroll.position.extentAfter < 500)
        loadOlder();
    });
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void dispose() {
    historyScroll.dispose();
    announcement.dispose();
    if (widget.updates?.activeChannel == widget.channelId) {
      widget.updates?.activeChannel = previousChannel;
      widget.updates?.activeChannelVisible = previousVisible;
    }
    timer?.cancel();
    super.dispose();
  }

  Future<void> searchHistory(String query, {bool media = false}) async {
    setState(() {
      postQuery = query;
      mediaOnly = media;
      posts = [];
      reactions = [];
      hasMore = true;
      loading = true;
    });
    await load(reset: true);
  }

  Future<void> loadOlder() async {
    if (busy || !hasMore || posts.isEmpty || reloadRequested) return;
    busy = true;
    final query = postQuery, onlyMedia = mediaOnly, cursor = posts.last;
    try {
      final rows =
          (await widget.repo.rpc('channel_history', {
                    'p_channel': widget.channelId,
                    'p_query': query,
                    'p_media': onlyMedia,
                    'p_before': cursor['created_at'],
                    'p_cursor': cursor['id'],
                  })
                  as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
      final ids = rows.map((p) => p['id'] as String).toList();
      final r = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await widget.repo.db
                .from('pulse_post_reactions')
                .select()
                .inFilter('post_id', ids);
      if (mounted && query == postQuery && onlyMedia == mediaOnly)
        setState(() {
          hasMore = rows.length == 30;
          final seen = posts.map((p) => p['id']).toSet();
          posts.addAll(rows.where((p) => seen.add(p['id'])));
          reactions.addAll(r);
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not load older announcements. Retry below.',
        );
    } finally {
      busy = false;
      if (reloadRequested && mounted) {
        reloadRequested = false;
        unawaited(load(reset: true));
      }
    }
  }

  Future<void> load({bool reset = false}) async {
    if (busy) {
      reloadRequested = reloadRequested || reset;
      return;
    }
    busy = true;
    final query = postQuery, onlyMedia = mediaOnly;
    try {
      final db = widget.repo.db;
      final summary = await widget.repo.rpc('channel_summary', {
        'p_channel': widget.channelId,
      });
      if (summary == null) {
        if (mounted)
          setState(() {
            channel = null;
            posts = [];
            reactions = [];
          });
        throw StateError('Channel unavailable');
      }
      final c = Map<String, dynamic>.from(summary as Map);
      final a = await widget.repo.rpc('channel_admin', {
        'p_channel': widget.channelId,
      });
      final f = await db
          .from('pulse_followers')
          .select()
          .eq('channel_id', widget.channelId)
          .eq('user_id', widget.repo.uid)
          .maybeSingle();
      final p =
          (await widget.repo.rpc('channel_history', {
                    'p_channel': widget.channelId,
                    'p_query': query,
                    'p_media': onlyMedia,
                  })
                  as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
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
      if (!mounted || query != postQuery || onlyMedia != mediaOnly) return;
      setState(() {
        channel = c;
        admin = a == true;
        followed = f != null;
        if (reset || posts.length <= 30) {
          posts = p;
          hasMore = p.length == 30;
          reactions = r;
        } else {
          final seen = p.map((p) => p['id']).toSet();
          posts = [...p, ...posts.where((p) => !seen.contains(p['id']))];
          reactions = [
            ...r,
            ...reactions.where((v) => !seen.contains(v['post_id'])),
          ];
        }
        live = l.isEmpty ? null : l.first;
        loading = false;
        error = null;
      });
      if ((a == true || f != null) &&
          p.isNotEmpty &&
          query.isEmpty &&
          !onlyMedia &&
          (!historyScroll.hasClients || historyScroll.offset < 100) &&
          visibilityRoute?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        try {
          await widget.updates?.read(widget.channelId, post: p.first['id']);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted && query == postQuery && onlyMedia == mediaOnly)
        setState(() {
          loading = false;
          error = 'Could not load channel. Check your connection.';
        });
    } finally {
      busy = false;
      if (reloadRequested && mounted) {
        reloadRequested = false;
        unawaited(load(reset: true));
      }
    }
  }

  Future<void> composeMedia(String kind) async {
    await PulseMedia.pauseAll();
    if (!mounted) return;
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelComposer(
          repo: widget.repo,
          channel: widget.channelId,
          kind: kind,
        ),
      ),
    );
    if (published == true && mounted) await searchHistory('');
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
    if (username == null || !mounted) return;
    await action(() async {
      final user = await widget.repo.db
          .from('pulse_profiles')
          .select('id')
          .eq('username', username.toLowerCase().replaceFirst('@', ''))
          .maybeSingle();
      if (user == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No Pulse account was found with that username.'),
            ),
          );
        return;
      }
      await widget.repo.rpc('channel_set_admin', {
        'p_channel': widget.channelId,
        'p_user': user['id'],
        'p_enabled': true,
      });
    });
  }

  Future<void> goLive() async {
    try {
      final eligibility =
          await widget.repo.rpc('live_tools', {
                'p_action': 'eligibility',
                'p_channel': widget.channelId,
              })
              as Map;
      if (!mounted) return;
      if (eligibility['eligible'] != true) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Unlock channel LIVE'),
            content: Text(
              'Channel administrators can go live once the channel reaches ${eligibility['minimum']} followers. Current followers: ${eligibility['followers']}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      if (mounted) channelError(context, e);
      return;
    }
    if (!mounted) return;
    final title = await channelPrompt(context, 'Livestream title', max: 100);
    if (title == null) return;
    try {
      final response = await widget.repo.db.functions.invoke(
        'pulse-live',
        body: {
          'action': 'start',
          'party_version': 1,
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

  Future<void> channelInfo() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseAvatar(
              repo: widget.repo,
              path: channel?['avatar_path'],
              name: channel?['name'] ?? 'Channel',
              radius: 58,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    channel?['name'] ?? 'Channel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (channel?['verified'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.verified, color: Colors.blue),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${channel?['followers'] ?? 0} followers'),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: followed ? 'Unfollow channel' : 'Follow channel',
                      onPressed: () {
                        Navigator.pop(sheet);
                        action(() async {
                          await widget.repo.rpc('follow_channel', {
                            'p_channel': widget.channelId,
                            'p_follow': !followed,
                          });
                          await widget.repo.refresh();
                        });
                      },
                      icon: Icon(followed ? Icons.check : Icons.add),
                    ),
                    Text(followed ? 'Following' : 'Follow'),
                  ],
                ),
                Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Search announcements',
                      onPressed: () async {
                        Navigator.pop(sheet);
                        final q = await channelPrompt(
                          context,
                          'Search announcements',
                          max: 100,
                        );
                        if (q != null && mounted) await searchHistory(q);
                      },
                      icon: const Icon(Icons.search),
                    ),
                    const Text('Search'),
                  ],
                ),
                Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Media history',
                      onPressed: () {
                        Navigator.pop(sheet);
                        searchHistory('', media: true);
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    Text('${channel?['media_count'] ?? 0} media'),
                  ],
                ),
                if (admin)
                  Column(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Edit channel',
                        onPressed: () {
                          Navigator.pop(sheet);
                          edit();
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      const Text('Edit'),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  channel?['description'] ?? '',
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ),
            Text(
              channel?['is_private'] == true
                  ? 'Private channel'
                  : 'Public channel',
              style: Theme.of(sheet).textTheme.labelLarge,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
  Future<void> sendAnnouncement() async {
    final body = announcement.text.trim();
    if (body.isEmpty || busy || sendingAnnouncement) return;
    setState(() => sendingAnnouncement = true);
    try {
      await action(() async {
        await widget.repo.rpc('channel_post', {
          'p_channel': widget.channelId,
          'p_body': body,
        });
        if (mounted) announcement.clear();
      });
    } finally {
      if (mounted) setState(() => sendingAnnouncement = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: channel == null ? null : channelInfo,
        child: Row(
          children: [
            PulseAvatar(
              repo: widget.repo,
              path: channel?['avatar_path'],
              name: channel?['name'] ?? 'Channel',
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      channel?['name'] ?? 'Channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                  if (channel?['verified'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(Icons.verified, size: 18, color: Colors.blue),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search announcements',
          onPressed: () async {
            final q = await channelPrompt(
              context,
              'Search announcements',
              max: 100,
            );
            if (q != null && mounted) await searchHistory(q);
          },
          icon: const Icon(Icons.search),
        ),
        if (admin)
          IconButton(
            tooltip: 'Change channel picture',
            onPressed: photo,
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
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
              if (postQuery.isNotEmpty || mediaOnly)
                ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(mediaOnly ? 'Media announcements' : postQuery),
                  trailing: IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => searchHistory(''),
                    icon: const Icon(Icons.close),
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
                  onRefresh: () => load(reset: true),
                  child: ListView.builder(
                    controller: historyScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: posts.length + 1,
                    itemBuilder: (_, i) {
                      if (i == posts.length)
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: posts.isEmpty
                              ? Text(
                                  postQuery.isEmpty && !mediaOnly
                                      ? 'No announcements yet.'
                                      : 'No matching announcements.',
                                )
                              : hasMore
                              ? TextButton(
                                  onPressed: loadOlder,
                                  child: const Text('Load older announcements'),
                                )
                              : const Text(
                                  'Beginning of channel',
                                  textAlign: TextAlign.center,
                                ),
                        );
                      final post = posts[i];
                      final all = reactions
                          .where((r) => r['post_id'] == post['id'])
                          .toList();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (post['attachment_path'] != null)
                                        ChannelPostMedia(
                                          key: ValueKey(post['id']),
                                          repo: widget.repo,
                                          post: post,
                                        ),
                                      if (post['body'].toString().isNotEmpty)
                                        SelectableText(
                                          post['body'],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            height: 1.45,
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '${post['created_at']}'.substring(
                                            0,
                                            16,
                                          ),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                    ],
                                  ),
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
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (admin)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: announcement,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 8000,
                      decoration: InputDecoration(
                        hintText: 'Announcement',
                        prefixIcon: PopupMenuButton<String>(
                          tooltip: 'Add media',
                          icon: const Icon(Icons.add_circle_outline),
                          enabled: !sendingAnnouncement,
                          onSelected: composeMedia,
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'image', child: Text('Photo')),
                            PopupMenuItem(value: 'video', child: Text('Video')),
                            PopupMenuItem(
                              value: 'audio',
                              child: Text('Voice note'),
                            ),
                          ],
                        ),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Send announcement',
                          onPressed: busy || sendingAnnouncement
                              ? null
                              : sendAnnouncement,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ),
                    ),
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
  late final party = PulseLiveParty(widget.repo, widget.sessionId);
  bool onStage = false, joiningStage = false;
  DateTime lastPermissionSync = DateTime.fromMillisecondsSinceEpoch(0);
  List<Map<String, dynamic>> chat = [];
  Timer? timer;
  bool connected = false,
      muted = false,
      sending = false,
      ending = false,
      polling = false;
  String? error;
  Map<String, dynamic> tools = {};
  bool liveActionBusy = false, camera = true;
  bool get canModerate => widget.host || tools['moderator'] == true;
  bool get canChat =>
      connected &&
      (widget.host || tools['chat_enabled'] != false) &&
      !(DateTime.tryParse(
            tools['muted_until']?.toString() ?? '',
          )?.isAfter(DateTime.now()) ??
          false);

  Future<void> liveAction(
    String action, {
    String? user,
    Map<String, dynamic> data = const {},
  }) async {
    if (liveActionBusy) return;
    setState(() => liveActionBusy = true);
    try {
      await widget.repo.rpc('live_tools', {
        'p_action': action,
        'p_session': widget.sessionId,
        'p_user': user,
        'p_data': data,
      });
      await poll();
    } catch (e) {
      if (mounted) channelError(context, e);
    } finally {
      if (mounted) setState(() => liveActionBusy = false);
    }
  }

  Future<void> liveSettings() async {
    var enabled = tools['chat_enabled'] != false;
    var seconds = (tools['slow_seconds'] as num?)?.toInt() ?? 2;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('LIVE chat controls'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow fan comments'),
                value: enabled,
                onChanged: (v) => update(() => enabled = v),
              ),
              DropdownButtonFormField<int>(
                initialValue: seconds,
                decoration: const InputDecoration(
                  labelText: 'Seconds between comments',
                ),
                items: [
                  for (final value in {
                    2,
                    5,
                    10,
                    30,
                    60,
                    120,
                    seconds,
                  }.toList()..sort())
                    DropdownMenuItem(
                      value: value,
                      child: Text('$value seconds'),
                    ),
                ],
                onChanged: (v) => update(() => seconds = v ?? 2),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted)
      await liveAction(
        'settings',
        data: {'chat_enabled': enabled, 'slow_seconds': seconds},
      );
  }

  @override
  void initState() {
    super.initState();
    party.addListener(changed);
    room.addListener(changed);
    connect();
  }

  void changed() {
    if (mounted)
      setState(() => connected = room.connectionState.name == 'connected');
  }

  Future<void> connect() async {
    try {
      final data =
          widget.initial ??
          Map<String, dynamic>.from(
            (await widget.repo.db.functions.invoke(
              'pulse-live',
              body: {
                'action': 'join',
                'session_id': widget.sessionId,
                'party_version': 1,
              },
            )).data,
          );
      await room.connect(data['url'], data['token']);
      await party.refresh();
      if (widget.host) await joinStage();
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
    } catch (connectionError) {
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
      if (mounted) setState(() => error = liveErrorMessage(connectionError));
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
          DateTime.parse(
            session['expires_at'],
          ).isBefore(DateTime.now().toUtc())) {
        timer?.cancel();
        await room.disconnect();
        if (mounted)
          setState(() {
            connected = false;
            error = 'This livestream has ended.';
          });
        return;
      }
      await party.refresh();
      if (!widget.host && onStage && party.state != 'approved') {
        await room.localParticipant?.setCameraEnabled(false);
        await room.localParticipant?.setMicrophoneEnabled(false);
        onStage = false;
      }
      if (widget.host &&
          DateTime.now().difference(lastPermissionSync).inSeconds >= 12) {
        await party.sync(reconcile: true);
        lastPermissionSync = DateTime.now();
      }
      final info = await widget.repo.rpc('live_tools', {
        'p_action': 'info',
        'p_session': widget.sessionId,
      });
      final rows = await widget.repo.db
          .from('pulse_live_chat')
          .select('*,pulse_profiles(display_name)')
          .eq('session_id', widget.sessionId)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted)
        setState(() {
          chat = rows.reversed.toList();
          tools = Map<String, dynamic>.from(info as Map);
          if (error == 'Live chat is reconnecting…') error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'Live chat is reconnecting…');
    } finally {
      polling = false;
    }
  }

  Future<void> joinStage() async {
    if (joiningStage) return;
    if (mounted) setState(() => joiningStage = true);
    try {
      final access = await party.sync();
      if (access['publish'] != true)
        throw StateError('Your seat is not approved.');
      for (
        var attempt = 0;
        attempt < 25 && room.localParticipant?.permissions.canPublish != true;
        attempt++
      ) {
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!mounted) return;
      if (room.localParticipant?.permissions.canPublish != true)
        throw StateError(
          'Stage permissions are still syncing. Try joining again.',
        );
      final video = widget.host || access['mode'] == 'video';
      await room.localParticipant?.setCameraEnabled(video);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (mounted)
        setState(() {
          onStage = true;
          camera = video;
          muted = false;
        });
    } catch (_) {
      await room.localParticipant?.setCameraEnabled(false);
      await room.localParticipant?.setMicrophoneEnabled(false);
      if (mounted) setState(() => onStage = false);
      rethrow;
    } finally {
      if (mounted) setState(() => joiningStage = false);
    }
  }

  Future<void> guestAction() async {
    try {
      if (onStage || party.state == 'pending') {
        await room.localParticipant?.setCameraEnabled(false);
        await room.localParticipant?.setMicrophoneEnabled(false);
        if (mounted) setState(() => onStage = false);
        await party.action('leave');
      } else if (party.state == 'approved') {
        await joinStage();
      } else {
        final mode = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Request a party seat'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'audio'),
                child: const ListTile(
                  leading: Icon(Icons.mic_none),
                  title: Text('Audio only'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'video'),
                child: const ListTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text('Camera and microphone'),
                ),
              ),
            ],
          ),
        );
        if (mode != null) await party.action('request', mode: mode);
      }
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  Future<void> end() async {
    if (ending) return;
    setState(() => ending = true);
    try {
      await room.localParticipant?.setCameraEnabled(false);
      await room.localParticipant?.setMicrophoneEnabled(false);
      if (mounted) setState(() => onStage = false);
      if (widget.host)
        await widget.repo.db.functions.invoke(
          'pulse-live',
          body: {'action': 'end', 'session_id': widget.sessionId},
        );
      if (!widget.host &&
          (party.state == 'approved' || party.state == 'pending')) {
        try {
          await party.action('leave');
        } catch (_) {
          /* Leaving the viewer route must remain possible offline. */
        }
      }
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
    if (!canChat || sending || composer.text.trim().isEmpty) return;
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
    party.removeListener(changed);
    party.dispose();
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
                child: !connected || party.members.isEmpty
                    ? Center(
                        child: Text(
                          error ??
                              (connected
                                  ? 'Waiting for host video…'
                                  : 'Connecting…'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : PulsePartyGrid(room: room, party: party),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${room.connectionState.name} · ${room.remoteParticipants.length} other connected participants',
              ),
            ),
            if (error != null && track != null) Text(error!),
            if (connected)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: '${tools['likes'] ?? 0} likes',
                    onPressed: liveActionBusy
                        ? null
                        : () => liveAction(
                            'like',
                            data: {'enabled': tools['liked'] != true},
                          ),
                    icon: Icon(
                      tools['liked'] == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.pinkAccent,
                    ),
                  ),
                  Text('${tools['likes'] ?? 0}'),
                  if (canModerate)
                    IconButton(
                      tooltip: 'Party requests (${party.requests.length})',
                      onPressed: () => showPulsePartyRequests(context, party),
                      icon: Badge(
                        isLabelVisible: party.requests.isNotEmpty,
                        label: Text('${party.requests.length}'),
                        child: const Icon(Icons.groups_outlined),
                      ),
                    ),
                  if (!widget.host)
                    TextButton.icon(
                      onPressed: party.busy || joiningStage
                          ? null
                          : guestAction,
                      icon: Icon(
                        onStage ? Icons.logout : Icons.person_add_outlined,
                      ),
                      label: Text(
                        onStage
                            ? 'Leave stage'
                            : party.state == 'pending'
                            ? 'Cancel request'
                            : party.state == 'approved'
                            ? 'Join stage'
                            : 'Request seat',
                      ),
                    ),

                  if (!widget.host && canModerate)
                    IconButton(
                      tooltip: 'Chat controls',
                      onPressed: !canModerate || liveActionBusy
                          ? null
                          : liveSettings,
                      icon: const Icon(Icons.tune),
                    ),
                  if (onStage) ...[
                    if (widget.host || party.mode != 'audio')
                      IconButton(
                        tooltip: camera ? 'Turn camera off' : 'Turn camera on',
                        onPressed: () async {
                          try {
                            await room.localParticipant?.setCameraEnabled(
                              !camera,
                            );
                            if (mounted) setState(() => camera = !camera);
                          } catch (e) {
                            if (mounted) channelError(context, e);
                          }
                        },
                        icon: Icon(
                          camera ? Icons.videocam : Icons.videocam_off,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Chat controls',
                      onPressed: !canModerate || liveActionBusy
                          ? null
                          : liveSettings,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ],
              ),
            if (tools['pinned'] is Map)
              ListTile(
                dense: true,
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(
                  tools['pinned']['body'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: canModerate
                    ? IconButton(
                        tooltip: 'Unpin comment',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            liveAction('pin', data: {'message': null}),
                      )
                    : null,
              ),
            if (onStage && connected)
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
                    trailing: canModerate
                        ? PopupMenuButton<String>(
                            enabled: !liveActionBusy,
                            onSelected: (value) async {
                              if (value == 'hide') {
                                try {
                                  await widget.repo.rpc('live_chat_hide', {
                                    'p_message': m['id'],
                                  });
                                  await poll();
                                } catch (e) {
                                  if (mounted) channelError(context, e);
                                }
                              } else if (value == 'pin') {
                                await liveAction(
                                  'pin',
                                  data: {'message': m['id']},
                                );
                              } else {
                                await liveAction(
                                  value,
                                  user: m['user_id'],
                                  data: {'minutes': 10},
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'pin',
                                child: Text('Pin comment'),
                              ),
                              PopupMenuItem(
                                value: 'hide',
                                child: Text('Hide comment'),
                              ),
                              PopupMenuItem(
                                value: 'mute',
                                child: Text('Mute fan for 10 minutes'),
                              ),
                              PopupMenuItem(
                                value: 'unmute',
                                child: Text('Unmute fan'),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ),
            if (connected && !canChat)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Fan chat is paused or you are temporarily muted.'),
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
                          enabled: canChat,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => send(),
                          maxLength: 500,
                          decoration: const InputDecoration(
                            hintText: 'Fan chat · followers only',
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: sending || !canChat ? null : send,
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
