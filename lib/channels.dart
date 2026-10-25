import 'package:wakelock_plus/wakelock_plus.dart';
import 'live_ui.dart';
import 'social_profile.dart';
import 'social_repository.dart' show SocialStore;
import 'gift_cinematic.dart';
import 'gifter_ranks.dart';
import 'channel_responses.dart';
import 'notifications.dart';
import 'package:share_plus/share_plus.dart';
import 'live_party.dart';
import 'live_gifts.dart';
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
                      'Follow channels. Stay close to every update.',
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
                              followed
                                  ? Icons.check_circle
                                  : Icons.chevron_right,
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
  Map<String, dynamic>? channel;
  List<Map<String, dynamic>> posts = [], reactions = [];
  bool admin = false, followed = false, loading = true, busy = false;
  bool channelMuted = false;
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
    PulseNotifications.instance.channelMuted(widget.channelId).then((value) {
      if (mounted) setState(() => channelMuted = value);
    });
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                          child: Icon(
                            Icons.verified,
                            size: 18,
                            color: Colors.blue,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    "${channel?['followers'] ?? 0} followers",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: channelMuted ? 'Unmute channel' : 'Mute channel',
          icon: Icon(
            channelMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
          ),
          onPressed: () async {
            final next = !channelMuted;
            try {
              await PulseNotifications.instance.muteChannel(
                widget.channelId,
                next,
              );
              if (mounted) setState(() => channelMuted = next);
            } catch (e) {
              if (mounted) channelError(context, e);
            }
          },
        ),
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
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => load(reset: true),
                  child: ListView.builder(
                    controller: historyScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    reverse: true,
                    padding: const EdgeInsets.all(12),
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
                                      if (post['quoted_body'] != null)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            border: Border(
                                              left: BorderSide(
                                                width: 4,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            post['quoted_body'],
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
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
                                  children: [
                                    IconButton(
                                      tooltip: 'Share announcement',
                                      icon: const Icon(
                                        Icons.ios_share,
                                        size: 19,
                                      ),
                                      onPressed: () => SharePlus.instance.share(
                                        ShareParams(
                                          text:
                                              "${channel?['name'] ?? 'Pulse channel'}\n${post['body']}",
                                        ),
                                      ),
                                    ),
                                    if (admin)
                                      IconButton(
                                        tooltip: 'Quote announcement',
                                        icon: const Icon(
                                          Icons.format_quote,
                                          size: 19,
                                        ),
                                        onPressed: () async {
                                          final body = await channelPrompt(
                                            context,
                                            'Reply to announcement',
                                            max: 4000,
                                          );
                                          if (body == null) return;
                                          await action(() async {
                                            await widget.repo
                                                .rpc('channel_quote', {
                                                  'p_channel': widget.channelId,
                                                  'p_post': post['id'],
                                                  'p_body': body,
                                                });
                                          });
                                        },
                                      ),
                                    TextButton.icon(
                                      onPressed: () => showChannelResponses(
                                        context,
                                        widget.repo,
                                        post['id'],
                                      ),
                                      icon: const Icon(
                                        Icons.mode_comment_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Respond'),
                                    ),
                                    ...['❤️', '🔥', '👏', '👍', '🎉'].map((
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
                                  ],
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
                  child: Text('Only administrators can post channel updates.'),
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

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  final chatScroll = ScrollController();
  final giftsKey = GlobalKey<PulseLiveGiftsState>();
  String? hostId;
  String hostFollowState = 'none';
  bool followingHost = false;
  Future<void>? shutdownFuture;
  final room = lk.Room(
    roomOptions: const lk.RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultCameraCaptureOptions: lk.CameraCaptureOptions(
        params: lk.VideoParametersPresets.h720_169,
        maxFrameRate: 30,
      ),
    ),
  );
  final composer = TextEditingController();
  late final party = PulseLiveParty(widget.repo, widget.sessionId);
  bool onStage = false,
      joiningStage = false,
      liveEnded = false,
      paused = false,
      connecting = false;
  final giftQueue = <Map<String, dynamic>>[];
  DateTime? crownUntil;
  Map<String, Map> chatRanks = {};
  bool likeBurst = false;
  bool giftSounds = true;
  String liveStyle = 'classic';
  Timer? likeTimer;
  String liveOwnerLabel = 'The host';
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
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable().catchError((_) {}));
    party.addListener(changed);
    room.addListener(changed);
    connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ending) return;
    unawaited(
      (state == AppLifecycleState.resumed
              ? WakelockPlus.enable()
              : WakelockPlus.disable())
          .catchError((_) {}),
    );
  }

  void changed() {
    if (mounted)
      setState(() => connected = room.connectionState.name == 'connected');
  }

  Future<void> connect() async {
    if (connecting || ending || liveEnded) return;
    connecting = true;
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
      final sessionInfo = await widget.repo.db
          .from('pulse_live_sessions')
          .select('host_id,channel_id')
          .eq('id', widget.sessionId)
          .single();
      hostId = sessionInfo['host_id'] as String;
      final hostProfile = await widget.repo.rpc('social_profile', {
        'p_user': hostId,
      });
      liveOwnerLabel = hostProfile?['display_name']?.toString() ?? 'The host';
      hostFollowState = hostProfile?['follow_state']?.toString() ?? 'none';
      if (!mounted || ending) return;
      await room.connect(data['url'], data['token']);
      if (!mounted || ending) {
        await room.disconnect();
        return;
      }
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
      timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      await poll();
    } catch (connectionError) {
      // A failed join is recoverable; never end a host's live as a side effect.
      await room.disconnect();
      if (mounted) setState(() => error = liveErrorMessage(connectionError));
    } finally {
      connecting = false;
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
          .maybeSingle();
      if (session == null ||
          session['status'] != 'live' ||
          DateTime.parse(
            session['expires_at'],
          ).isBefore(DateTime.now().toUtc())) {
        timer?.cancel();
        unawaited(room.disconnect().catchError((_) {}));
        if (mounted)
          setState(() {
            connected = false;
            liveEnded = true;
            error = '$liveOwnerLabel has quit the live.';
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
          .select('*,pulse_profiles(display_name,avatar_path,username)')
          .eq('session_id', widget.sessionId)
          .order('created_at', ascending: false)
          .limit(100);
      final rankData =
          await widget.repo.rpc('gifter_ranks', {
                'p_users': rows.map((r) => r['user_id']).toSet().toList(),
              })
              as List;
      final latestChanged =
          rows.isNotEmpty &&
          (chat.isEmpty || chat.first['id'] != rows.first['id']);
      if (mounted)
        setState(() {
          chatRanks = {
            for (final r in rankData.whereType<Map>())
              r['user_id'] as String: r,
          };
          chat = rows.toList();
          tools = Map<String, dynamic>.from(info as Map);
          if (error == 'Live chat is reconnecting…') error = null;
        });
      if (mounted && latestChanged)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (chatScroll.hasClients)
            chatScroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
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

  Future<void> shutdown() async {
    timer?.cancel();
    // Notify viewers and stop capture independently. A stalled camera method
    // must not delay the host's end notice, nor a stalled API delay disconnect.
    final notifyServer = leaveServer();
    await Future.wait([
      () async {
        try {
          await room.localParticipant
              ?.setCameraEnabled(false)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }(),
      () async {
        try {
          await room.localParticipant
              ?.setMicrophoneEnabled(false)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }(),
    ]);
    try {
      await room.disconnect().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await room.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await notifyServer;
  }

  Future<void> leaveServer() async {
    try {
      if (widget.host && !liveEnded) {
        try {
          await widget.repo.db.functions
              .invoke(
                'pulse-live',
                body: {'action': 'end', 'session_id': widget.sessionId},
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          await widget.repo
              .rpc('live_end', {'p_session': widget.sessionId})
              .timeout(const Duration(seconds: 4));
        }
      } else if (!widget.host &&
          (party.state == 'approved' || party.state == 'pending')) {
        await widget.repo.db.functions
            .invoke(
              'pulse-live',
              body: {
                'action': 'party',
                'party_action': 'leave',
                'session_id': widget.sessionId,
              },
            )
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  Future<void> end() async {
    if (ending) return;
    setState(() => ending = true);
    timer?.cancel();
    // Close the viewer immediately; media/server cleanup must never block Back.
    shutdownFuture ??= shutdown();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> openProfile(String user) async {
    final store = SocialStore(widget.repo);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: SocialProfile(
              store: store,
              user: user,
              liveNavigation: false,
            ),
          ),
        ),
      );
    } finally {
      store.dispose();
    }
  }

  Future<void> followHost() async {
    if (hostId == null || followingHost) return;
    setState(() => followingHost = true);
    try {
      final result = await widget.repo.rpc('social_follow', {
        'p_user': hostId,
        'p_follow': true,
      });
      if (mounted) setState(() => hostFollowState = result.toString());
    } catch (e) {
      if (mounted) channelError(context, e);
    } finally {
      if (mounted) setState(() => followingHost = false);
    }
  }

  Future<void> moderateComment(Map<String, dynamic> message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in {
              'pin': 'Pin comment',
              'hide': 'Hide comment',
              'mute': 'Mute for 10 minutes',
              'unmute': 'Unmute',
            }.entries)
              ListTile(
                title: Text(item.value),
                onTap: () => Navigator.pop(c, item.key),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'hide') {
      try {
        await widget.repo.rpc('live_chat_hide', {'p_message': message['id']});
        await poll();
      } catch (e) {
        if (mounted) channelError(context, e);
      }
    } else
      await liveAction(
        action,
        user: message['user_id'],
        data: action == 'pin' ? {'message': message['id']} : {'minutes': 10},
      );
  }

  Future<void> showLiveMenu() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .65,
          child: AnimatedBuilder(
            animation: party,
            builder: (_, __) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ListTile(
                  title: Text(
                    'LIVE menu',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                  ),
                ),
                if (canModerate)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('Seat requests & guests'),
                    trailing: Badge(
                      isLabelVisible: party.requests.isNotEmpty,
                      label: Text('${party.requests.length}'),
                      child: const Icon(Icons.chevron_right),
                    ),
                    onTap: () => Navigator.pop(c, 'seats'),
                  ),
                if (!widget.host)
                  ListTile(
                    leading: const Icon(Icons.person_add_outlined),
                    title: Text(
                      onStage
                          ? 'Leave seat'
                          : party.state == 'pending'
                          ? 'Cancel seat request'
                          : party.state == 'approved'
                          ? 'Join approved seat'
                          : 'Request a seat',
                    ),
                    onTap: () => Navigator.pop(c, 'guest'),
                  ),
                if (widget.host)
                  ListTile(
                    leading: Icon(paused ? Icons.play_arrow : Icons.pause),
                    title: Text(paused ? 'Resume live' : 'Pause live'),
                    onTap: () => Navigator.pop(c, 'pause'),
                  ),
                if (onStage)
                  ListTile(
                    leading: Icon(muted ? Icons.mic_off : Icons.mic),
                    title: Text(
                      muted ? 'Unmute microphone' : 'Mute microphone',
                    ),
                    onTap: () => Navigator.pop(c, 'mic'),
                  ),
                if (onStage && (widget.host || party.mode != 'audio'))
                  ListTile(
                    leading: Icon(camera ? Icons.videocam : Icons.videocam_off),
                    title: Text(camera ? 'Turn camera off' : 'Turn camera on'),
                    onTap: () => Navigator.pop(c, 'camera'),
                  ),
                if (canModerate)
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Comment controls'),
                    onTap: () => Navigator.pop(c, 'chat'),
                  ),
                ListTile(
                  leading: const Icon(Icons.card_giftcard),
                  title: const Text('Gifts, wallet & battles'),
                  onTap: () => Navigator.pop(c, 'gifts'),
                ),
                ListTile(
                  leading: Icon(
                    giftSounds ? Icons.volume_up : Icons.volume_off,
                  ),
                  title: Text(
                    giftSounds ? 'Mute gift sounds' : 'Enable gift sounds',
                  ),
                  onTap: () => Navigator.pop(c, 'gift_sounds'),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(
                    liveStyle == 'cinema' ? 'Show comments' : 'Hide comments',
                  ),
                  onTap: () => Navigator.pop(c, 'comments'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Share LIVE'),
                  onTap: () => Navigator.pop(c, 'share'),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(widget.host ? 'End live' : 'Leave live'),
                  onTap: () => Navigator.pop(c, 'leave'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    try {
      switch (selected) {
        case 'seats':
          await showPulsePartyRequests(context, party);
          break;
        case 'guest':
          await guestAction();
          break;
        case 'pause':
          await pauseOrResume();
          break;
        case 'chat':
          await liveSettings();
          break;
        case 'gifts':
          await giftsKey.currentState?.showControls(context);
          break;
        case 'share':
          await SharePlus.instance.share(
            ShareParams(
              text:
                  'Watch $liveOwnerLabel LIVE on Pulse. Open Pulse and find their profile to join. https://iszyisrael04-art.github.io/Pulse-web/',
            ),
          );
          break;
        case 'gift_sounds':
          setState(() => giftSounds = !giftSounds);
          break;
        case 'comments':
          setState(
            () => liveStyle = liveStyle == 'cinema' ? 'classic' : 'cinema',
          );
          break;
        case 'mic':
          await room.localParticipant?.setMicrophoneEnabled(muted);
          if (mounted) setState(() => muted = !muted);
          break;
        case 'camera':
          await room.localParticipant?.setCameraEnabled(!camera);
          if (mounted) setState(() => camera = !camera);
          break;
        case 'leave':
          await end();
          break;
      }
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  Future<void> pauseOrResume() async {
    if (!widget.host || !connected || liveEnded || joiningStage) return;
    try {
      if (paused) {
        await joinStage();
      } else {
        await room.localParticipant?.setCameraEnabled(false);
        await room.localParticipant?.setMicrophoneEnabled(false);
        onStage = false;
      }
      if (mounted) setState(() => paused = !paused);
    } catch (e) {
      if (mounted) channelError(context, e);
    }
  }

  Future<void> likeLive() async {
    if (!connected || liveEnded) return;
    setState(() => likeBurst = true);
    likeTimer?.cancel();
    likeTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => likeBurst = false);
    });
    if (tools['liked'] == true || liveActionBusy) return;
    await liveAction('like', data: {'enabled': true});
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
    likeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable().catchError((_) {}));
    shutdownFuture ??= shutdown();
    party.removeListener(changed);
    party.dispose();
    room.removeListener(changed);
    chatScroll.dispose();
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = party.data['host'] is Map
        ? party.data['host'] as Map
        : const {};
    final viewers = connected
        ? pulseLiveViewerCount(
            room.remoteParticipants.keys,
            room.localParticipant?.identity,
            hostId,
          )
        : 0;
    return PopScope(
      canPop: ending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) end();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (context, bounds) => Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                left: 0,
                right: 0,
                top: party.members.length > 1
                    ? MediaQuery.paddingOf(context).top + 70
                    : 0,
                height: party.members.length > 1
                    ? bounds.maxHeight * .56
                    : bounds.maxHeight,
                child: GestureDetector(
                  onDoubleTap: likeLive,
                  behavior: HitTestBehavior.opaque,
                  child: connected && party.members.isNotEmpty
                      ? PulsePartyGrid(
                          room: room,
                          party: party,
                          crownUntil: crownUntil,
                        )
                      : Center(
                          child: Text(
                            liveEnded
                                ? '$liveOwnerLabel has ended the live.'
                                : error ?? 'Connecting…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                ),
              ),
              if (paused)
                const Center(
                  child: Text(
                    'LIVE paused',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (likeBurst)
                const Center(
                  child: IgnorePointer(
                    child: Icon(
                      Icons.favorite,
                      color: Colors.pinkAccent,
                      size: 96,
                    ),
                  ),
                ),
              if (giftQueue.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: PulseLiveGiftPresentation(
                      key: ValueKey(
                        '${giftQueue.first['is_test']}:${giftQueue.first['id']}',
                      ),
                      repo: widget.repo,
                      event: giftQueue.first,
                      sound: giftSounds,
                      fast: giftQueue.length > 5,
                      onComplete: () {
                        if (mounted && giftQueue.isNotEmpty) {
                          setState(() {
                            giftQueue.removeAt(0);
                            if (giftQueue.isNotEmpty &&
                                giftQueue.first['sku'] == 'crown') {
                              crownUntil = DateTime.now().add(
                                const Duration(seconds: 12),
                              );
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: PulseLiveHeader(
                    avatar: PulseAvatar(
                      repo: widget.repo,
                      path: host['avatar_path'],
                      name: liveOwnerLabel,
                      userId: hostId,
                      radius: 17,
                    ),
                    name: liveOwnerLabel,
                    viewers: viewers,
                    openProfile: () {
                      if (hostId != null) openProfile(hostId!);
                    },
                    leave: ending ? null : end,
                    follow:
                        !widget.host &&
                            hostId != null &&
                            hostFollowState != 'accepted' &&
                            hostFollowState != 'pending' &&
                            !followingHost
                        ? followHost
                        : null,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xcc000000)],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              error!,
                              maxLines: 2,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        if (!connected && !liveEnded && !ending)
                          TextButton.icon(
                            onPressed: () {
                              timer?.cancel();
                              connect();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reconnect'),
                          ),
                        if (tools['pinned'] is Map)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.push_pin_outlined,
                              color: Colors.white70,
                            ),
                            title: Text(
                              tools['pinned']['body'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        if (liveStyle != 'cinema')
                          SizedBox(
                            height: (bounds.maxHeight * .24).clamp(76.0, 180.0),
                            child: ListView.builder(
                              controller: chatScroll,
                              reverse: true,
                              padding: const EdgeInsets.only(bottom: 4),
                              itemCount: chat.length,
                              itemBuilder: (_, i) {
                                final m = chat[i],
                                    p = m['pulse_profiles'] as Map? ?? {};
                                return PulseLiveComment(
                                  avatar: PulseAvatar(
                                    repo: widget.repo,
                                    path: p['avatar_path'],
                                    name: p['display_name'] ?? 'Pulse fan',
                                    userId: m['user_id'],
                                    radius: 15,
                                  ),
                                  name: p['display_name'] ?? 'Pulse fan',
                                  message: m['body'] ?? '',
                                  openProfile: () => openProfile(m['user_id']),
                                  rank: PulseRankBadge(
                                    rank:
                                        (chatRanks[m['user_id']]?['rank']
                                                    as num? ??
                                                0)
                                            .toInt(),
                                    size: 20,
                                  ),
                                  moderate: canModerate
                                      ? () => moderateComment(m)
                                      : null,
                                );
                              },
                            ),
                          ),
                        if (connected)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: PulseLiveMessageField(
                                    controller: composer,
                                    enabled: canChat && !sending,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Send message',
                                  onPressed: sending || !canChat ? null : send,
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                  ),
                                ),
                                PulseLiveGifts(
                                  key: giftsKey,
                                  repo: widget.repo,
                                  session: widget.sessionId,
                                  host: widget.host,
                                  compact: true,
                                  onGift: (event) {
                                    if (mounted)
                                      setState(() {
                                        if (giftQueue.isEmpty &&
                                            event['sku'] == 'crown') {
                                          crownUntil = DateTime.now().add(
                                            const Duration(seconds: 12),
                                          );
                                        }
                                        if (giftQueue.length >= 20)
                                          giftQueue.removeAt(1);
                                        giftQueue.add(event);
                                      });
                                  },
                                ),
                                if (MediaQuery.viewInsetsOf(context).bottom ==
                                    0)
                                  PulseLiveMenuButton(
                                    requests: canModerate
                                        ? party.requests.length
                                        : 0,
                                    onPressed: showLiveMenu,
                                  ),
                                if (MediaQuery.viewInsetsOf(context).bottom ==
                                        0 &&
                                    bounds.maxWidth >= 390)
                                  IconButton(
                                    tooltip: 'Share LIVE',
                                    onPressed: () => SharePlus.instance.share(
                                      ShareParams(
                                        text:
                                            'Watch $liveOwnerLabel LIVE on Pulse. Open Pulse and find their profile to join. https://iszyisrael04-art.github.io/Pulse-web/',
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.ios_share,
                                      color: Colors.white,
                                    ),
                                  ),
                                if (MediaQuery.viewInsetsOf(context).bottom ==
                                    0)
                                  IconButton(
                                    tooltip: 'Like LIVE',
                                    onPressed: likeLive,
                                    icon: Icon(
                                      tools['liked'] == true
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: Colors.pinkAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
