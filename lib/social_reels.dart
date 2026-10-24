import 'dart:io';
import 'reel_prefetch.dart';
import 'social_download.dart';
import 'activity.dart';
import 'social_context.dart';
import 'appearance.dart';
import 'social_media.dart';
import 'playback_status.dart';
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
  final prefetch = PulseReelPrefetch();
  File? activeCache;
  String? likedAnimationPost;
  Timer? likeAnimationTimer;
  final likingPosts = <String>{};
  Player? player;
  VideoController? video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final counted = <String>{};
  int index = 0;
  String? desired, loaded, error;
  Timer? playbackErrorTimer;
  Timer? startupDeadline;
  Duration lastPlaybackPosition = Duration.zero;
  bool pumping = false, buffering = false, muted = false, playing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feed = SocialFeedController(widget.store, kind: 'reel', mode: 'for_you')
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
    await prefetch.clear();
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

  Future<void> doubleTapLike(Map<String, dynamic> post) async {
    final id = post['id'] as String;
    setState(() => likedAnimationPost = id);
    likeAnimationTimer?.cancel();
    likeAnimationTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => likedAnimationPost = null);
    });
    if (post['liked'] == true || !likingPosts.add(id)) return;
    try {
      await widget.store.action(id, 'like', true);
      final updated = await widget.store.post(id);
      if (mounted) feed.change(updated, id);
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      likingPosts.remove(id);
    }
  }

  Future<void> select(int next) async {
    playbackErrorTimer?.cancel();
    lastPlaybackPosition = Duration.zero;
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

  void armPlaybackDeadline(String wanted) {
    startupDeadline?.cancel();
    final before = lastPlaybackPosition;
    startupDeadline = Timer(const Duration(seconds: 18), () {
      if (mounted &&
          desired == wanted &&
          (lastPlaybackPosition == before || buffering)) {
        player?.pause();
        setState(
          () => error =
              'Playback is taking too long. Check your connection, then retry.',
        );
      }
    });
  }

  Future<void> pump() async {
    if (pumping) return;
    pumping = true;
    try {
      while (mounted && desired != null && desired != loaded) {
        final wanted = desired!;
        armPlaybackDeadline(wanted);
        final match = feed.rows.where((r) => r['id'] == wanted);
        if (match.isEmpty) break;
        final row = match.first;
        try {
          final mediaPath = (row['media'] as List).first['path'] as String;
          final url = await widget.store
              .signed((row['media'] as List).first['path'], renew: true)
              .timeout(const Duration(seconds: 12));
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
                if (mounted)
                  setState(() {
                    playing = v;
                    if (v) error = null;
                  });
              }),
            );
            subscriptions.add(
              player!.stream.buffering.listen((v) {
                if (mounted) {
                  setState(() => buffering = v);
                  if (v && playing && desired != null)
                    armPlaybackDeadline(desired!);
                }
              }),
            );
            subscriptions.add(
              player!.stream.error.listen((_) {
                // Codec/network warnings can be followed by successful frames.
                // Only show a failure if this same Reel stops advancing.
                final observed = player;
                final wanted = desired;
                final before = observed?.state.position;
                playbackErrorTimer?.cancel();
                playbackErrorTimer = Timer(
                  const Duration(milliseconds: 1200),
                  () {
                    if (!mounted ||
                        player != observed ||
                        desired != wanted ||
                        observed == null)
                      return;
                    if (before != null && observed.state.position > before)
                      return;
                    setState(
                      () => error =
                          'Playback interrupted. Check your connection or retry.',
                    );
                  },
                );
              }),
            );
            subscriptions.add(
              player!.stream.position.listen((position) {
                final id = loaded;
                if (id == desired &&
                    player!.state.playing &&
                    error != null &&
                    position > lastPlaybackPosition) {
                  setState(() => error = null);
                }
                if (id == desired) {
                  if (position > lastPlaybackPosition) {
                    startupDeadline?.cancel();
                    if (lastPlaybackPosition == Duration.zero && mounted)
                      setState(() {});
                  }
                  lastPlaybackPosition = position;
                }
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
          final oldCache = activeCache;
          activeCache = null;
          if (oldCache != null) {
            try {
              if (await oldCache.exists()) await oldCache.delete();
            } catch (_) {}
          }
          if (!mounted) return;
          if (desired != wanted) continue;
          await player!.setVolume(muted ? 0 : 100);
          await player!.setPlaylistMode(PlaylistMode.single);
          activeCache = prefetch.take(mediaPath);
          await player!
              .open(Media(activeCache?.path ?? url), play: false)
              .timeout(const Duration(seconds: 18));
          if (!mounted) return;
          if (desired != wanted) continue;
          loaded = wanted;
          error = null;
          await PulseMedia.activate(player!);
          await player!.play();
          if (!mounted) return;
          if (WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed &&
              index + 1 < feed.rows.length) {
            final nextPath =
                (feed.rows[index + 1]['media'] as List).first['path'] as String;
            unawaited(
              prefetch.warm(
                nextPath,
                () => widget.store.signed(nextPath, renew: true),
              ),
            );
          }
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
    if (state != AppLifecycleState.resumed) {
      player?.pause();
      unawaited(prefetch.clear());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playbackErrorTimer?.cancel();
    likeAnimationTimer?.cancel();
    startupDeadline?.cancel();
    unawaited(prefetch.clear());
    desired = null;
    feed.removeListener(changed);
    feed.dispose();
    pages.dispose();
    for (final s in subscriptions) {
      s.cancel();
    }
    if (PulseMedia.active == player) PulseMedia.active = null;
    final current = player;
    if (current != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        current.dispose().then((_) async {
          final cached = activeCache;
          if (cached != null) {
            try {
              if (await cached.exists()) await cached.delete();
            } catch (_) {}
          }
        });
      });
    super.dispose();
  }

  Widget playbackTimeline() {
    final p = player;
    if (p == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      initialData: p.state.position,
      builder: (_, snapshot) {
        final total = p.state.duration.inMilliseconds;
        final position = (snapshot.data ?? Duration.zero).inMilliseconds
            .clamp(0, total > 0 ? total : 0)
            .toDouble();
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: position,
            max: total > 0 ? total.toDouble() : 1,
            onChanged: total <= 0
                ? null
                : (v) => p.seek(Duration(milliseconds: v.round())),
          ),
        );
      },
    );
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
                    fontSize: 22,
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
                            onDoubleTap: () => doubleTapLike(post),
                            child: Video(
                              controller: video!,
                              fit: BoxFit.contain,
                              controls: NoVideoControls,
                            ),
                          )
                        else
                          const DecoratedBox(decoration: pulseVideoGradient),
                        if ((!active ||
                                loaded != post['id'] ||
                                lastPlaybackPosition == Duration.zero ||
                                error != null) &&
                            (post['media'] as List).first['cover_path'] != null)
                          SocialImage(
                            store: widget.store,
                            path: (post['media'] as List).first['cover_path'],
                            fit: BoxFit.cover,
                            quiet: true,
                          ),
                        if (active &&
                            (loaded != post['id'] ||
                                buffering ||
                                lastPlaybackPosition == Duration.zero ||
                                error != null))
                          PulsePlaybackStatus(
                            loading: error == null,
                            message: error,
                            onRetry: error == null
                                ? null
                                : () {
                                    loaded = null;
                                    error = null;
                                    lastPlaybackPosition = Duration.zero;
                                    setState(() {});
                                    pump();
                                  },
                          ),
                        if (active &&
                            loaded == post['id'] &&
                            !playing &&
                            error == null &&
                            lastPlaybackPosition > Duration.zero)
                          const Center(
                            child: IgnorePointer(
                              child: Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 72,
                              ),
                            ),
                          ),
                        if (likedAnimationPost == post['id'])
                          const Center(
                            child: IgnorePointer(
                              child: Icon(
                                Icons.favorite,
                                size: 110,
                                color: Colors.pinkAccent,
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
                                      userId: author['id'],
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
                                        '${post['promoted'] == true ? 'Promoted · ' : ''}@${author['username'] ?? 'pulse_user'}',
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
                              PulseDownloadProgress(postId: post['id']),
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
                          bottom: 42,
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
                        Positioned(
                          left: 8,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 14,
                                  color: Color(0xff8cebd7),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'For You',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (active && loaded == post['id'])
                          Positioned(
                            left: 4,
                            right: 4,
                            bottom: 0,
                            child: playbackTimeline(),
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
