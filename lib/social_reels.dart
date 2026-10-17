import 'activity.dart';
import 'social_context.dart';
import 'appearance.dart';
import 'social_hashtags.dart';
import 'social_search.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'avatar.dart';
import 'media.dart';
import 'social_repository.dart';
import 'social_actions.dart';
import 'social_common.dart';

class PulseReels extends StatefulWidget {
  const PulseReels({super.key, required this.store});
  final SocialStore store;
  @override
  State<PulseReels> createState() => _PulseReelsState();
}

class _PulseReelsState extends State<PulseReels> with WidgetsBindingObserver {
  late final SocialFeedController feed;
  final pages = PageController();
  Player? player;
  VideoController? video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final counted = <String>{};
  int index = 0;
  String? desired, loaded, error;
  bool pumping = false, buffering = false, muted = false, playing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feed = SocialFeedController(widget.store, kind: 'reel')
      ..addListener(changed);
    feed.load(reset: true);
  }

  void changed() {
    if (!mounted) return;
    if (desired == null && !feed.loading && index < feed.rows.length) {
      desired = feed.rows[index]['id'];
      pump();
    }
    setState(() {});
  }

  Future<void> refresh() async {
    desired = null;
    loaded = null;
    index = 0;
    // Clear the old page before jump callbacks can select its content.
    final loading = feed.load(reset: true);
    await player?.pause();
    if (!mounted) return;
    if (pages.hasClients) pages.jumpToPage(0);
    await loading;
  }

  Future<void> select(int next) async {
    index = next;
    loaded = null;
    error = null;
    desired = next < feed.rows.length ? feed.rows[next]['id'] : null;
    await player?.pause();
    if (!mounted) return;
    setState(() {});
    if (next >= feed.rows.length - 3) feed.load();
    await pump();
  }

  Future<void> pump() async {
    if (pumping) return;
    pumping = true;
    try {
      while (mounted && desired != null && desired != loaded) {
        final wanted = desired!;
        final match = feed.rows.where((r) => r['id'] == wanted);
        if (match.isEmpty) break;
        final row = match.first;
        try {
          final url = await widget.store.signed(
            (row['media'] as List).first['path'],
            renew: true,
          );
          if (!mounted) return;
          if (desired != wanted) continue;
          if (player == null) {
            MediaKit.ensureInitialized();
            player = Player(
              configuration: const PlayerConfiguration(
                bufferSize: 8 * 1024 * 1024,
              ),
            );
            video = VideoController(player!);
            subscriptions.add(
              player!.stream.playing.listen((v) {
                if (mounted) setState(() => playing = v);
              }),
            );
            subscriptions.add(
              player!.stream.buffering.listen((v) {
                if (mounted) setState(() => buffering = v);
              }),
            );
            subscriptions.add(
              player!.stream.error.listen((_) {
                if (mounted)
                  setState(
                    () => error =
                        'Video unavailable. Retry or swipe to the next Reel.',
                  );
              }),
            );
            subscriptions.add(
              player!.stream.position.listen((position) {
                final id = loaded;
                if (id != null &&
                    position.inSeconds >= 3 &&
                    player!.state.playing &&
                    counted.add(id)) {
                  if (counted.length > 512) counted.remove(counted.first);
                  widget.store.action(id, 'view', true).catchError((_) {
                    counted.remove(id);
                  });
                }
              }),
            );
          }
          await player!.stop();
          if (!mounted) return;
          if (desired != wanted) continue;
          await player!.setVolume(muted ? 0 : 100);
          await player!.setPlaylistMode(PlaylistMode.single);
          await player!.open(Media(url), play: false);
          if (!mounted) return;
          if (desired != wanted) continue;
          loaded = wanted;
          error = null;
          await PulseMedia.activate(player!);
          await player!.play();
          if (mounted) setState(() {});
        } catch (e) {
          if (!mounted) return;
          if (desired == wanted) {
            setState(() => error = socialError(e));
            break;
          }
        }
      }
    } finally {
      pumping = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    desired = null;
    feed.removeListener(changed);
    feed.dispose();
    pages.dispose();
    for (final s in subscriptions) {
      s.cancel();
    }
    if (PulseMedia.active == player) PulseMedia.active = null;
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Reels',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PulseActivityButton(store: widget.store, color: Colors.white),
              IconButton(
                tooltip: 'Search PULSE',
                onPressed: () => openPulseSearch(context, widget.store),
                icon: const Icon(Icons.search, color: Colors.white),
              ),
              IconButton(
                tooltip: 'Refresh Reels',
                onPressed: refresh,
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
              IconButton(
                tooltip: muted ? 'Enable sound' : 'Mute sound',
                onPressed: () async {
                  muted = !muted;
                  await player?.setVolume(muted ? 0 : 100);
                  if (mounted) setState(() {});
                },
                icon: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: feed.rows.isEmpty
              ? Center(
                  child: feed.loading
                      ? const PulseLoader()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              feed.error ??
                                  'No Reels yet. Upload your first video.',
                              style: const TextStyle(color: Colors.white),
                            ),
                            TextButton(
                              onPressed: refresh,
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                )
              : PageView.builder(
                  controller: pages,
                  scrollDirection: Axis.vertical,
                  itemCount: feed.rows.length + 1,
                  onPageChanged: select,
                  itemBuilder: (context, i) {
                    if (i == feed.rows.length)
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (feed.loading)
                              const PulseLoader()
                            else
                              Text(
                                feed.error ??
                                    (feed.hasMore
                                        ? 'Load more Reels'
                                        : 'You’re all caught up.'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            TextButton(
                              onPressed: feed.hasMore
                                  ? () => feed.load()
                                  : refresh,
                              child: Text(
                                feed.hasMore ? 'Load more' : 'Back to newest',
                              ),
                            ),
                          ],
                        ),
                      );
                    final post = feed.rows[i],
                        author = Map<String, dynamic>.from(
                          feed.rows[i]['author'] as Map,
                        );
                    final active = i == index;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (active && loaded == post['id'] && video != null)
                          GestureDetector(
                            onSecondaryTapDown: (details) =>
                                pulseContentContext(
                                  context,
                                  widget.store,
                                  post,
                                  details.globalPosition,
                                  (updated) => feed.change(updated, post['id']),
                                ),
                            onTap: () => player?.playOrPause(),
                            child: Video(
                              controller: video!,
                              fit: BoxFit.contain,
                              controls: NoVideoControls,
                            ),
                          )
                        else
                          const ColoredBox(color: Colors.black),
                        if (active &&
                            (loaded != post['id'] ||
                                buffering ||
                                error != null))
                          Center(
                            child: error == null
                                ? const PulseLoader()
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        error!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          loaded = null;
                                          pump();
                                        },
                                        child: const Text('Retry video'),
                                      ),
                                    ],
                                  ),
                          ),
                        if (active && loaded == post['id'] && !playing)
                          const Center(
                            child: IgnorePointer(
                              child: Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 72,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 250,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 24,
                          right: 100,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () async {
                                  await player?.pause();
                                  if (context.mounted)
                                    openCreator(
                                      context,
                                      widget.store,
                                      post['author_id'],
                                    );
                                },
                                child: Row(
                                  children: [
                                    PulseAvatar(
                                      repo: widget.store.repo,
                                      path: author['avatar_path'],
                                      name: author['display_name'],
                                      radius: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    if (author['verified'] == true)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.verified,
                                          color: Colors.blue,
                                          size: 18,
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        '@${author['username'] ?? 'pulse_user'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                post['body'],
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              SocialHashtags(
                                store: widget.store,
                                body: post['body'],
                                light: true,
                              ),
                              Text(
                                '${post['views']} unique views',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 20,
                          child: SizedBox(
                            width: 88,
                            child: SocialActions(
                              store: widget.store,
                              post: post,
                              vertical: true,
                              onChanged: (p) {
                                feed.change(p, post['id']);
                                if (p == null) {
                                  select(index.clamp(0, feed.rows.length));
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
