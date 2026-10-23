import 'package:flutter/material.dart';
import 'activity_labels.dart';
export 'activity_labels.dart';
import 'activity_controller.dart';
import 'avatar.dart';
import 'appearance.dart';
import 'media.dart';
import 'social_common.dart';
import 'social_repository.dart';

class PulseActivityButton extends StatelessWidget {
  const PulseActivityButton({super.key, required this.store, this.color});
  final SocialStore store;
  final Color? color;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store.activity,
    builder: (_, __) => IconButton(
      tooltip: 'Activity notifications',
      onPressed: () async {
        await PulseMedia.pauseAll();
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PulseActivityPage(store: store)),
        );
        store.activity.refresh();
      },
      icon: Badge(
        isLabelVisible: store.activity.unread > 0,
        label: Text(
          store.activity.unread > 99 ? '99+' : '${store.activity.unread}',
        ),
        child: Icon(Icons.notifications_outlined, color: color),
      ),
    ),
  );
}

class PulseActivityPage extends StatefulWidget {
  const PulseActivityPage({super.key, required this.store});
  final SocialStore store;
  @override
  State<PulseActivityPage> createState() => _PulseActivityPageState();
}

class _PulseActivityPageState extends State<PulseActivityPage> {
  PulseActivityController get controller => widget.store.activity;
  final scroll = ScrollController();
  List<Map<String, dynamic>> items = [];
  String? error, asOf;
  bool loading = false, more = true, changing = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    controller.viewing++;
    load(reset: true);
    scroll.addListener(() {
      if (scroll.position.extentAfter < 400) load();
    });
  }

  @override
  void dispose() {
    generation++;
    controller.viewing--;
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading || (!reset && !more)) return;
    final own = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await controller.page(
        cursor: reset || items.isEmpty ? null : items.last,
      );
      if (!mounted || generation != own) return;
      final page = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        if (reset) {
          items = [];
          asOf = data['as_of'] as String?;
        }
        final ids = items.map((e) => e['id']).toSet();
        items.addAll(page.where((e) => ids.add(e['id'])));
        more = page.length == 30;
      });
    } catch (_) {
      if (mounted && generation == own)
        setState(
          () => error =
              'Could not load activity. Check your connection and retry.',
        );
    } finally {
      if (mounted && generation == own) setState(() => loading = false);
    }
  }

  Future<void> open(Map<String, dynamic> row, {bool profile = false}) async {
    try {
      if (row['read'] != true) {
        await controller.read(id: row['id'] as String);
        if (mounted) setState(() => row['read'] = true);
      }
      if (!mounted) return;
      if (profile || row['post_id'] == null) {
        await openCreator(
          context,
          widget.store,
          row['kind'] == 'follow_request' && !profile
              ? widget.store.uid
              : row['actor_id'] as String,
        );
      } else {
        await openSocialPost(context, widget.store, row['post_id'] as String);
      }
      if (mounted) await load(reset: true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This notification is unavailable or the connection was lost.',
            ),
          ),
        );
    }
  }

  Future<void> markAll() async {
    if (asOf == null || changing) return;
    setState(() => changing = true);
    try {
      await controller.read(until: asOf);
      if (mounted) await load(reset: true);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not mark notifications read. Please retry.',
        );
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> preferences() async {
    var selected = Map<String, bool>.from(controller.preferences);
    bool saving = false;
    String? failure;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (c, set) => PopScope<Object?>(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Activity notifications'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in {
                      'mentions': 'Tags & mentions',
                      'follows': 'Followers & follow requests',
                      'likes': 'Likes on your posts & videos',
                      'comments': 'Comments on your content',
                      'following': 'New posts & videos from following',
                    }.entries)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.value),
                        value: selected[entry.key] == true,
                        onChanged: saving
                            ? null
                            : (v) => set(() => selected[entry.key] = v),
                      ),
                    const Text(
                      'Controls this in-app inbox. Closed-app push delivery is not configured yet.',
                      style: TextStyle(fontSize: 12),
                    ),
                    if (failure != null) Text(failure!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        set(() {
                          saving = true;
                          failure = null;
                        });
                        try {
                          await controller.savePreferences(selected);
                          if (dialog.mounted) Navigator.pop(dialog, true);
                        } catch (_) {
                          if (dialog.mounted)
                            set(
                              () => failure =
                                  'Could not save preferences. Please retry.',
                            );
                        } finally {
                          if (dialog.mounted) set(() => saving = false);
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (changed == true && mounted) await load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Activity'),
      actions: [
        IconButton(
          tooltip: 'Mark all read',
          onPressed: changing || loading || items.isEmpty ? null : markAll,
          icon: const Icon(Icons.done_all),
        ),
        IconButton(
          tooltip: 'Notification preferences',
          onPressed: loading ? null : preferences,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: Column(
      children: [
        if (loading || changing) const LinearProgressIndicator(),
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: () => load(reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(reset: true),
            child: ListView(
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (items.isEmpty && !loading && error == null)
                  const Padding(
                    padding: EdgeInsets.all(36),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none, size: 54),
                        SizedBox(height: 12),
                        Text('You’re all caught up'),
                        SizedBox(height: 8),
                        Text(
                          'New mentions, followers and activity from people you follow will appear here.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                for (final row in items)
                  ListTile(
                    tileColor: row['read'] == true
                        ? null
                        : Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: .28),
                    leading: InkWell(
                      onTap: () => open(row, profile: true),
                      customBorder: const CircleBorder(),
                      child: PulseAvatar(
                        repo: widget.store.repo,
                        path: row['avatar_path'],
                        name: row['display_name'] ?? 'Pulse user',
                      ),
                    ),
                    title: Text(
                      '${row['display_name']} ${(row['kind'] == 'community_tag' ? 'tagged ${row['community_name'] ?? 'your community'}' : pulseActivityAction(row['kind'] as String, video: row['is_video'] == true))}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: row['read'] == true
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '@${row['username'] ?? 'pulse_user'}${(row['preview'] as String? ?? '').isEmpty ? '' : '\n${row['preview']}'}\n${pulseActivityTime(row['created_at']?.toString(), DateTime.now())}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: row['read'] == true
                        ? const Icon(Icons.done, size: 17)
                        : Icon(
                            Icons.circle,
                            size: 9,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    onTap: () => open(row),
                  ),
                if (more && items.isNotEmpty)
                  TextButton(
                    onPressed: loading ? null : load,
                    child: loading
                        ? const PulseLoader(size: 20)
                        : const Text('Load more'),
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Activity from the last 90 days. Pull down to refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
