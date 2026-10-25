import 'profile_banner.dart';
import 'profile_tools_sheet.dart';
import 'profile_hero.dart';
import 'offline_videos.dart';
import 'gifter_ranks.dart';
import 'channels.dart';
import 'dart:async';
import 'profile_identity.dart';
import 'communities.dart';
import 'profile_rules.dart';
import 'creator_access.dart';
import 'appearance.dart';

import 'package:flutter/material.dart';

import 'avatar.dart';
import 'presence_widgets.dart';
import 'statuses.dart';
import 'profile.dart';
import 'social_repository.dart';
import 'social_feed.dart';
import 'social_media.dart';
import 'social_common.dart';

class SocialProfile extends StatefulWidget {
  const SocialProfile({
    super.key,
    required this.store,
    required this.user,
    this.settings,
    this.liveNavigation = true,
  });
  final SocialStore store;
  final String user;
  final VoidCallback? settings;
  final bool liveNavigation;
  @override
  State<SocialProfile> createState() => _SocialProfileState();
}

class _SocialProfileState extends State<SocialProfile> {
  SocialRow? profile;
  Map? liveSession;
  String? error;
  bool loading = false, busy = false;
  int tab = 0;
  bool admin = false;
  String profileStyle = 'classic';
  Map features = {};
  Timer? featureRefresh;
  Future<void> addStory() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add story')),
            for (final item in [
              ('image', 'Photo story', Icons.photo_outlined),
              ('video', 'Video story', Icons.videocam_outlined),
              ('text', 'Text story', Icons.text_fields),
            ])
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                onTap: () => Navigator.pop(c, item.$1),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Your story')),
          body: StatusUpdates(repo: widget.store.repo, initialPostType: type),
        ),
      ),
    );
  }

  @override
  void dispose() {
    featureRefresh?.cancel();
    widget.store.removeListener(profileChanged);
    super.dispose();
  }

  bool get mine => widget.user == widget.store.uid;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(profileChanged);
    load();
  }

  bool reloadPending = false;
  void profileChanged() {
    if (loading) {
      reloadPending = true;
      return;
    }
    load();
  }

  @override
  void didUpdateWidget(SocialProfile old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      old.store.removeListener(profileChanged);
      widget.store.addListener(profileChanged);
    }
    if (old.user != widget.user || old.store != widget.store) profileChanged();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final user = widget.user;
      final result = await widget.store.profile(user);
      final identity = await widget.store.repo.rpc('profile_features', {
        'p_user': widget.user,
      });
      final live = await widget.store.repo.rpc('personal_live', {
        'p_action': 'info',
        'p_user': user,
      });
      final style = identity is Map
          ? identity['background'] as String? ?? 'classic'
          : 'classic';
      final isAdmin = mine
          ? await widget.store.repo.rpc('is_admin', {}) == true
          : false;
      if (!mounted || user != widget.user) return;
      setState(() {
        profile = result;
        liveSession = live is Map ? live['session'] as Map? : null;
        profileStyle = style;
        features = identity is Map ? identity : {};
        admin = isAdmin;
        error = null;
      });
      featureRefresh?.cancel();
      final until = DateTime.tryParse(
        features['motion_until']?.toString() ?? '',
      );
      if (until != null && until.isAfter(DateTime.now())) {
        featureRefresh = Timer(
          until.difference(DateTime.now()) + const Duration(milliseconds: 30),
          () {
            if (!mounted) return;
            setState(() {
              profileStyle = 'classic';
              features = {};
            });
            load();
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (reloadPending) {
          reloadPending = false;
          load();
        }
      }
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Edit profile')),
          body: ProfilePanel(
            repo: widget.store.repo,
            onSaved: () async {
              await widget.store.repo.refresh();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> requests() async {
    try {
      final data = await widget.store.rpc('requests', {});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Follow requests'),
          content: SizedBox(
            width: 420,
            height: 350,
            child: (data as List).isEmpty
                ? const Text('No pending requests')
                : ListView(
                    children: data
                        .map(
                          (p) => ListTile(
                            title: Text(p['display_name']),
                            subtitle: Text('@${p['username'] ?? 'pulse_user'}'),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Approve',
                                  onPressed: () {
                                    Navigator.pop(c);
                                    perform(() async {
                                      await widget.store.rpc('approve', {
                                        'p_user': p['id'],
                                        'p_accept': true,
                                      });
                                    });
                                  },
                                  icon: const Icon(Icons.check),
                                ),
                                IconButton(
                                  tooltip: 'Decline',
                                  onPressed: () {
                                    Navigator.pop(c);
                                    perform(() async {
                                      await widget.store.rpc('approve', {
                                        'p_user': p['id'],
                                        'p_accept': false,
                                      });
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  void showProfileTools(SocialRow p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        VoidCallback? action(VoidCallback callback) => busy
            ? null
            : () {
                Navigator.pop(sheetContext);
                callback();
              };
        return PulseProfileToolsSheet(
          groups: [
            PulseProfileToolGroup('Your profile', [
              PulseProfileTool(
                'Edit photo & profile',
                'Your name, photo and bio',
                Icons.person_outline,
                action(editProfile),
              ),
              PulseProfileTool(
                'Video banner',
                'Five-second video behind your portrait · Free',
                Icons.panorama_outlined,
                action(
                  () => perform(
                    () => editFreeProfileBanner(
                      context,
                      widget.store,
                      p['is_private'] == true,
                    ),
                  ),
                ),
              ),
              PulseProfileTool(
                'Background & Signal',
                'Choose a style and share what’s on your mind',
                Icons.palette_outlined,
                action(() async {
                  final changed = await editPulseIdentity(
                    context,
                    widget.store,
                    features,
                  );
                  if (changed == true && mounted) await load();
                }),
              ),
              PulseProfileTool(
                'Clear background & Signal',
                'Return to your classic profile style',
                Icons.restart_alt,
                action(
                  () => perform(() async {
                    await widget.store.repo.rpc('profile_features_save', {
                      'p_background': 'classic',
                      'p_signal': '',
                      'p_mode': 'creating',
                    });
                  }),
                ),
              ),
            ]),
            PulseProfileToolGroup('Creator tools', [
              PulseProfileTool(
                'Creator Studio',
                'Your posts, reach and engagement',
                Icons.insights_outlined,
                action(
                  () => showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Creator Studio'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final entry
                                in (p['analytics'] as Map? ?? {}).entries)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text('${entry.key}: ${entry.value}'),
                              ),
                            const Text(
                              'Views count unique signed-in viewers opening a post or watching 3 seconds of video. These self-reported beta metrics are not audited advertising metrics.',
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PulseProfileTool(
                'Animated profile & Boost',
                'Profile motion and promotion options',
                Icons.auto_awesome_outlined,
                action(() async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PulseCreatorAccessPage(store: widget.store),
                    ),
                  );
                  if (changed == true && mounted) await load();
                }),
              ),
              PulseProfileTool(
                'Offline videos',
                'Manage videos saved for offline viewing',
                Icons.offline_bolt_outlined,
                action(
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PulseOfflineVideos(user: widget.store.uid),
                    ),
                  ),
                ),
              ),
            ]),
            PulseProfileToolGroup('Privacy & audience', [
              PulseProfileTool(
                'Follow requests',
                'Review people requesting to follow you',
                Icons.person_add_alt_outlined,
                action(requests),
              ),
              PulseProfileTool(
                p['is_private'] == true ? 'Make public' : 'Make private',
                p['is_private'] == true
                    ? 'Let everyone on Pulse see your posts'
                    : 'Limit your posts to approved followers',
                p['is_private'] == true ? Icons.public : Icons.lock_outline,
                action(
                  () => perform(() async {
                    await widget.store.rpc('account', {
                      'p_private': p['is_private'] != true,
                      'p_cover': p['cover_path'],
                    });
                  }),
                ),
              ),
            ]),
            if (admin)
              PulseProfileToolGroup('Administration', [
                PulseProfileTool(
                  'Social moderation',
                  'Review reports and manage content',
                  Icons.shield_outlined,
                  action(
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SocialModeration(store: widget.store),
                      ),
                    ),
                  ),
                ),
              ]),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null)
      return Center(
        child: loading
            ? const PulseLoader()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error ?? 'Profile unavailable'),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
      );
    final modes = mine
        ? ['Posts', 'Reels', 'Saved', 'Drafts']
        : ['Posts', 'Reels'];
    final profileHeader = Column(
      children: [
        PulseProfileHero(
          background: PulseProfileBackdrop(
            style: profileStyle,
            child: (p['cover_path']?.toString() ?? '').endsWith('.mp4')
                ? PulseProfileBanner(
                    key: ValueKey('${widget.user}:${p['cover_path']}'),
                    store: widget.store,
                    path: p['cover_path'],
                    fill: true,
                  )
                : const SizedBox.expand(),
          ),
          avatar: Center(
            child: Tooltip(
              message: mine ? 'Add story' : 'View profile photo',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: mine
                    ? addStory
                    : () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          content: SizedBox.square(
                            dimension: 240,
                            child: PulseAvatar(
                              repo: widget.store.repo,
                              path: p['avatar_path'],
                              userId: widget.user,
                              name: p['display_name'],
                              radius: 120,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                child: SizedBox.square(
                  dimension: 112,
                  child: Stack(
                    children: [
                      PulseAvatar(
                        repo: widget.store.repo,
                        path: p['avatar_path'],
                        userId: widget.user,
                        name: p['display_name'],
                        radius: 54,
                      ),
                      if (liveSession != null)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: InkWell(
                            onTap: !widget.liveNavigation
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => LiveScreen(
                                        repo: widget.store.repo,
                                        sessionId: liveSession!['id'],
                                        host: mine,
                                      ),
                                    ),
                                  ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (mine)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton.filled(
                              tooltip: 'Add story',
                              onPressed: addStory,
                              icon: const Icon(Icons.add, size: 23),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          displayName: p['display_name']?.toString() ?? 'Pulse creator',
          username: p['username']?.toString() ?? 'pulse_user',
          following: p['following'],
          followers: p['followers'],
          likes: p['likes'] ?? p['analytics']?['likes'],
          verified: p['verified'] == true,
          signal: features['signal'] as String?,
          onEdit: mine ? editProfile : null,
          actions: [
            if (mine)
              IconButton(
                tooltip: 'Profile tools',
                onPressed: () => showProfileTools(p),
                icon: const Icon(Icons.more_horiz),
              ),
            IconButton(
              tooltip: widget.settings == null ? 'Refresh profile' : 'Settings',
              onPressed: widget.settings ?? load,
              icon: Icon(
                widget.settings == null
                    ? Icons.refresh
                    : Icons.settings_outlined,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PulseGifterIdentity(repo: widget.store.repo, user: widget.user),
              PulsePresenceLabel(
                presence: widget.store.repo.presence,
                userId: widget.user,
              ),
              PulseProfileCommunities(
                repo: widget.store.repo,
                user: widget.user,
              ),
              if ((p['bio']?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    p['bio'],
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              if (!mine)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          await widget.store.follow(
                            widget.user,
                            p['follow_state'] == 'none',
                          );
                        }),
                  child: Text(
                    p['follow_state'] == 'accepted'
                        ? 'Unfollow'
                        : p['follow_state'] == 'pending'
                        ? 'Cancel request'
                        : 'Follow',
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < modes.length; i++)
              Expanded(
                child: Semantics(
                  selected: tab == i,
                  child: Tooltip(
                    message: modes[i],
                    child: InkWell(
                      onTap: () => setState(() => tab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: tab == i
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Icon(
                          const [
                            Icons.grid_on_rounded,
                            Icons.play_circle_outline_rounded,
                            Icons.bookmark_border_rounded,
                            Icons.drafts_outlined,
                          ][i],
                          semanticLabel: modes[i],
                          color: tab == i
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return Column(
      children: [
        if (busy || loading) const LinearProgressIndicator(),
        Expanded(
          child: SocialFeed(
            key: ValueKey('${widget.user}:$tab'),
            store: widget.store,
            header: false,
            grid: true,
            profileHeader: profileHeader,
            onProfileRefresh: load,
            author: widget.user,
            mode: tab == 2
                ? 'saved'
                : tab == 3
                ? 'drafts'
                : 'profile',
            kind: tab == 0
                ? 'post'
                : tab == 1
                ? 'reel'
                : 'all',
          ),
        ),
      ],
    );
  }
}

class SocialModeration extends StatefulWidget {
  const SocialModeration({super.key, required this.store});
  final SocialStore store;
  @override
  State<SocialModeration> createState() => _SocialModerationState();
}

class _SocialModerationState extends State<SocialModeration> {
  List<SocialRow> reports = [];
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.store.repo.db
          .from('pulse_social_reports')
          .select()
          .eq('state', 'open')
          .order('created_at')
          .limit(50);
      if (mounted)
        setState(() {
          reports = data;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(String id) async {
    try {
      final value = await widget.store.rpc('review', {'p_id': id});
      if (!mounted || value == null) return;
      final post = Map<String, dynamic>.from(value as Map);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reported content'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(post['body']),
                  Text('State: ${post['state']} · Hidden: ${post['hidden']}'),
                  for (final media in post['media'] as List)
                    SizedBox(
                      height: 240,
                      child: media['kind'] == 'image'
                          ? SocialImage(
                              store: widget.store,
                              path: media['path'],
                            )
                          : SocialInlineVideo(
                              store: widget.store,
                              postId: id,
                              recordView: false,
                              path: media['path'],
                            ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Social moderation'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        Expanded(
          child: ListView(
            children: [
              if (reports.isEmpty && !busy)
                const ListTile(title: Text('No open reports')),
              for (final report in reports)
                ListTile(
                  title: Text(report['reason']),
                  subtitle: Text('Post: ${report['post_id']}'),
                  onTap: () => review(report['post_id']),
                  trailing: TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await widget.store.rpc('moderate', {
                                'p_id': report['post_id'],
                                'p_hide': true,
                              });
                              await load();
                            } catch (e) {
                              if (context.mounted) socialNotice(context, e);
                            }
                          },
                    child: const Text('Hide post'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
