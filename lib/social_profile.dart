import 'social_premium.dart';
import 'appearance.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'avatar.dart';
import 'media.dart';
import 'profile.dart';
import 'social_repository.dart';
import 'social_feed.dart';
import 'social_media.dart';
import 'social_common.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

class SocialProfile extends StatefulWidget {
  const SocialProfile({
    super.key,
    required this.store,
    required this.user,
    this.settings,
  });
  final SocialStore store;
  final String user;
  final VoidCallback? settings;
  @override
  State<SocialProfile> createState() => _SocialProfileState();
}

class _SocialProfileState extends State<SocialProfile> {
  SocialRow? profile;
  String? error;
  bool loading = false, busy = false;
  int tab = 0;
  bool admin = false;
  String profileStyle = 'classic';
  bool get mine => widget.user == widget.store.uid;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await widget.store.profile(widget.user);
      final style = await widget.store.rpc('profile_style', {
        'p_user': widget.user,
      });
      final isAdmin = mine
          ? await widget.store.repo.rpc('is_admin', {}) == true
          : false;
      if (mounted)
        setState(() {
          profile = result;
          profileStyle = style as String;
          admin = isAdmin;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => loading = false);
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

  Future<void> cover() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file?.path == null || !mounted) return;
    await perform(() async {
      final source = File(file!.path!);
      if (await source.length() > 10485760)
        throw SocialFailure('Cover photos must be under 10 MB');
      final mime = mimeFor(file.name),
          safe = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${widget.store.uid}/cover/${const Uuid().v4()}-$safe';
      await widget.store.repo.db.storage
          .from('pulse-social')
          .upload(path, source, fileOptions: FileOptions(contentType: mime));
      await widget.store.rpc('account', {
        'p_private': profile!['is_private'],
        'p_cover': path,
      });
    });
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
    return Column(
      children: [
        if (busy || loading) const LinearProgressIndicator(),
        SizedBox(
          height: MediaQuery.sizeOf(context).height < 720 ? 230 : 300,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (p['cover_path'] != null)
                SizedBox(
                  height: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SocialImage(
                      store: widget.store,
                      path: p['cover_path'],
                    ),
                  ),
                )
              else
                Container(
                  height: 75,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xff00bfa6),
                        Color(0xffa58bff),
                        Color(0xffff7c68),
                      ],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: profileStyle == 'classic'
                      ? null
                      : LinearGradient(
                          colors: profileStyle == 'aurora'
                              ? [
                                  const Color(0xff175c66),
                                  const Color(0xff553b86),
                                ]
                              : profileStyle == 'sunset'
                              ? [
                                  const Color(0xff9a4c43),
                                  const Color(0xff623a75),
                                ]
                              : [
                                  const Color(0xff142a4d),
                                  const Color(0xff252238),
                                ],
                        ),
                ),
                child: Theme(
                  data: profileStyle == 'classic'
                      ? Theme.of(context)
                      : Theme.of(context).copyWith(
                          listTileTheme: const ListTileThemeData(
                            textColor: Colors.white,
                            iconColor: Colors.white,
                          ),
                        ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PulseAvatar(
                      repo: widget.store.repo,
                      path: p['avatar_path'],
                      name: p['display_name'],
                      radius: 28,
                    ),
                    title: Wrap(
                      spacing: 5,
                      children: [
                        Text(
                          p['display_name'],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (p['verified'] == true)
                          const Icon(Icons.verified, color: Colors.blue),
                        if (p['premium'] == true)
                          const Icon(
                            Icons.workspace_premium,
                            color: Colors.amber,
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '@${p['username'] ?? 'pulse_user'} · ${p['is_private'] == true ? 'Private' : 'Public'}',
                    ),
                    trailing: widget.settings == null
                        ? IconButton(
                            tooltip: 'Refresh profile',
                            onPressed: load,
                            icon: const Icon(Icons.refresh),
                          )
                        : IconButton(
                            tooltip: 'Settings',
                            onPressed: widget.settings,
                            icon: const Icon(Icons.settings_outlined),
                          ),
                  ),
                ),
              ),
              if (p['bio'].toString().isNotEmpty) Text(p['bio']),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  children: [
                    for (final entry in {
                      'Followers': p['followers'],
                      'Following': p['following'],
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.value}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
              if (mine)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Premium profile theme'),
                      onPressed: () async {
                        if (p['premium'] != true) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PulsePremiumPage(store: widget.store),
                            ),
                          );
                          if (mounted) load();
                          return;
                        }
                        if (!mounted) return;
                        final theme = await showDialog<String>(
                          context: context,
                          builder: (c) => SimpleDialog(
                            title: const Text('Profile theme'),
                            children: [
                              for (final name in [
                                'classic',
                                'aurora',
                                'sunset',
                                'midnight',
                              ])
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(c, name),
                                  child: Text(name),
                                ),
                            ],
                          ),
                        );
                        if (theme != null)
                          await perform(
                            () => widget.store.rpc('set_profile_style', {
                              'p_theme': theme,
                            }),
                          );
                      },
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(
                                      title: const Text('Edit profile'),
                                    ),
                                    body: ProfilePanel(
                                      repo: widget.store.repo,
                                      onSaved: () async {
                                        await widget.store.repo.refresh();
                                        if (context.mounted)
                                          Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                ),
                              );
                              if (mounted) load();
                            },
                      child: const Text('Edit profile'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : cover,
                      child: const Text('Cover photo'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : requests,
                      child: const Text('Follow requests'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => perform(() async {
                              await widget.store.rpc('account', {
                                'p_private': p['is_private'] != true,
                                'p_cover': p['cover_path'],
                              });
                            }),
                      child: Text(
                        p['is_private'] == true
                            ? 'Make public'
                            : 'Make private',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Creator Studio'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry
                                  in (p['analytics'] as Map).entries)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text('${entry.key}: ${entry.value}'),
                                ),
                              const Text(
                                'Views count unique signed-in viewers opening a post or watching 3 seconds of video. These self-reported beta metrics are not audited advertising metrics.',
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Creator Studio'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final code = await socialPrompt(
                          context,
                          'Redeem Premium code',
                          limit: 40,
                        );
                        if (code == null || !mounted) return;
                        await perform(() async {
                          final result = await widget.store.repo.rpc(
                            'redeem_result',
                            {'p_code': code.trim()},
                          );
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Premium active until ${DateTime.parse(result['expires_at']).toLocal().toString().substring(0, 10)}',
                                ),
                              ),
                            );
                        });
                      },
                      child: const Text('Redeem code'),
                    ),
                    if (admin)
                      OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SocialModeration(store: widget.store),
                          ),
                        ),
                        child: const Text('Social moderation'),
                      ),
                  ],
                ),
              if (mine)
                const Text(
                  'Premium: \$3/month planned. No paid billing is enabled. Existing entitlements and one-time 30DAYSPULSE redemption are preserved.',
                  style: TextStyle(fontSize: 11),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < modes.length; i++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(modes[i]),
                    selected: tab == i,
                    onSelected: (_) => setState(() => tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SocialFeed(
            key: ValueKey('${widget.user}:$tab'),
            store: widget.store,
            header: false,
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
