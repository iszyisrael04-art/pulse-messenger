import 'appearance.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'media.dart';
import 'video_visibility.dart';
import 'social_repository.dart';

class SocialImage extends StatefulWidget {
  const SocialImage({super.key, required this.store, required this.path});
  final SocialStore store;
  final String path;
  @override
  State<SocialImage> createState() => _SocialImageState();
}

class _SocialImageState extends State<SocialImage> {
  late Future<String> url;
  @override
  void initState() {
    super.initState();
    url = widget.store.signed(widget.path);
  }

  @override
  void didUpdateWidget(SocialImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) url = widget.store.signed(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: url,
    builder: (_, s) {
      if (s.hasError)
        return Center(
          child: TextButton(
            onPressed: () => setState(
              () => url = widget.store.signed(widget.path, renew: true),
            ),
            child: const Text('Photo unavailable · retry'),
          ),
        );
      if (!s.hasData) return const Center(child: PulseLoader());
      return Image.network(
        s.data!,
        fit: BoxFit.contain,
        cacheWidth: 960,
        loadingBuilder: (_, child, loading) =>
            loading == null ? child : const Center(child: PulseLoader()),
        errorBuilder: (_, __, ___) => Center(
          child: TextButton(
            onPressed: () => setState(
              () => url = widget.store.signed(widget.path, renew: true),
            ),
            child: const Text('Reload photo'),
          ),
        ),
      );
    },
  );
}

class SocialInlineVideo extends StatefulWidget {
  const SocialInlineVideo({
    super.key,
    required this.store,
    required this.postId,
    required this.path,
    this.recordView = true,
    this.autoplay = true,
  });
  final SocialStore store;
  final bool recordView, autoplay;
  final String postId, path;
  @override
  State<SocialInlineVideo> createState() => _SocialInlineVideoState();
}

class _SocialInlineVideoState extends State<SocialInlineVideo>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  String? error;
  bool loading = false, viewed = false, userPaused = false, foreground = true;
  Timer? visibilityTimer;
  int playbackGeneration = 0;
  bool hasPlayed = false, muted = true;
  final subscriptions = <StreamSubscription<dynamic>>[];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoplay)
      visibilityTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => checkVisibility(),
      );
  }

  bool get visible {
    if (!mounted || !foreground || ModalRoute.of(context)?.isCurrent == false)
      return false;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached)
      return false;
    final top = render.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    final height = render.size.height;
    if (height <= 0) return false;
    return pulseVideoVisible(top, height, screen);
  }

  Future<void> releaseOffscreen() async {
    final old = player;
    player = null;
    controller = null;
    playbackGeneration++;
    hasPlayed = false;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    subscriptions.clear();
    if (old != null) PulseMedia.consumeAutomaticPause(old);
    if (PulseMedia.active == old) PulseMedia.active = null;
    if (mounted) setState(() {});
    await old?.dispose();
  }

  void checkVisibility() {
    if (!mounted || loading) return;
    if (!visible) {
      if (player != null) releaseOffscreen();
      return;
    }
    if (!userPaused && player == null && error == null)
      play(automatic: true);
    else if (!userPaused &&
        player != null &&
        !player!.state.playing &&
        PulseMedia.active == null)
      play(automatic: true);
  }

  Future<void> play({bool automatic = false}) async {
    if (loading) return;
    final own = playbackGeneration;
    if (!automatic) userPaused = false;
    setState(() {
      loading = true;
    });
    try {
      if (player != null && error == null) {
        await PulseMedia.activate(player!);
        userPaused = player!.state.playing;
        await player!.playOrPause();
        return;
      }
      if (player != null) {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
        final old = player!;
        if (PulseMedia.active == old) PulseMedia.active = null;
        player = null;
        controller = null;
        await old.dispose();
      }
      final url = await widget.store.signed(widget.path, renew: true);
      if (!mounted || own != playbackGeneration || automatic && !visible)
        return;
      MediaKit.ensureInitialized();
      player = Player(
        configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
      );
      controller = VideoController(player!);
      final observedPlayer = player!;
      subscriptions.add(
        observedPlayer.stream.playing.listen((playing) {
          if (!mounted || player != observedPlayer) return;
          if (playing) {
            hasPlayed = true;
            userPaused = false;
            PulseMedia.activate(observedPlayer)
                .then((_) {
                  if (!mounted || widget.autoplay && !visible)
                    observedPlayer.pause();
                })
                .catchError((_) {});
          } else if (PulseMedia.consumeAutomaticPause(observedPlayer)) {
            // Another visible clip or the app lifecycle paused this player.
          } else if (hasPlayed &&
              foreground &&
              visible &&
              PulseMedia.active == observedPlayer) {
            userPaused = true;
          }
        }),
      );
      subscriptions.add(
        player!.stream.error.listen((_) {
          if (mounted)
            setState(
              () => error = 'Video could not play. Try an optimized MP4.',
            );
        }),
      );
      subscriptions.add(
        player!.stream.position.listen((position) {
          if (player != observedPlayer) return;
          if (widget.recordView &&
              position.inSeconds >= 3 &&
              !viewed &&
              player!.state.playing) {
            viewed = true;
            widget.store.action(widget.postId, 'view', true).catchError((_) {
              viewed = false;
            });
          }
        }),
      );
      error = null;
      final current = player!;
      muted = automatic;
      await current.setVolume(muted ? 0 : 100);
      await PulseMedia.activate(current);
      await current.open(Media(url));
      if (PulseMedia.active != current) await current.pause();
      if (!mounted || automatic && !visible) await releaseOffscreen();
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      if (player != null) PulseMedia.markAutomaticPause(player!);
      player?.pause();
    } else if (player != null && !userPaused && visible) {
      PulseMedia.activate(
        player!,
      ).then((_) => player?.play()).catchError((_) {});
    } else
      checkVisibility();
  }

  @override
  void dispose() {
    visibilityTimer?.cancel();
    playbackGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) {
      s.cancel();
    }
    if (player != null) PulseMedia.consumeAutomaticPause(player);
    if (PulseMedia.active == player) PulseMedia.active = null;
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text(error!),
              TextButton(
                onPressed: loading ? null : play,
                child: const Text('Reload video'),
              ),
            ],
          ),
        ),
      Expanded(
        child: controller != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Video(controller: controller!),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: muted ? 'Enable sound' : 'Mute sound',
                        icon: Icon(
                          muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          final p = player;
                          if (p == null) return;
                          await p.setVolume(muted ? 100 : 0);
                          if (mounted) setState(() => muted = !muted);
                        },
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: loading
                    ? const PulseLoader()
                    : FilledButton.icon(
                        onPressed: play,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play video'),
                      ),
              ),
      ),
    ],
  );
}

/// Backfills a first-frame cover for older video drafts without stored covers.
/// Capture is serialized and the native player is released immediately afterward.
class SocialDraftCover extends StatefulWidget {
  const SocialDraftCover({super.key, required this.store, required this.media});
  final SocialStore store;
  final Map media;
  @override
  State<SocialDraftCover> createState() => _SocialDraftCoverState();
}

class _SocialDraftCoverState extends State<SocialDraftCover> {
  static Future<void> queue = Future<void>.value();
  Uint8List? cover;
  Player? player;
  VideoController? video;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.media['kind'] == 'video' && widget.media['cover_path'] == null) {
      queue = queue.catchError((_) {}).then((_) => capture());
    }
  }

  Future<void> capture() async {
    if (!mounted) return;
    Player? own;
    try {
      final url = await widget.store.signed(widget.media['path']);
      if (!mounted) return;
      MediaKit.ensureInitialized();
      own = Player(
        configuration: const PlayerConfiguration(bufferSize: 6 * 1024 * 1024),
      );
      player = own;
      video = VideoController(own);
      setState(() {});
      await own.open(Media(url), play: false);
      for (var i = 0; i < 12 && mounted; i++) {
        final bytes = await own.screenshot(format: 'image/jpeg');
        if (bytes != null && bytes.isNotEmpty) {
          cover = bytes;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (cover == null) error = 'Cover unavailable';
    } catch (_) {
      error = 'Cover unavailable';
    } finally {
      if (player == own) {
        player = null;
        video = null;
        if (mounted) setState(() {});
        await own?.dispose();
      }
    }
  }

  @override
  void dispose() {
    final old = player;
    player = null;
    old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path =
        widget.media['cover_path'] ??
        (widget.media['kind'] == 'image' ? widget.media['path'] : null);
    if (path != null) return SocialImage(store: widget.store, path: path);
    if (cover != null)
      return Image.memory(cover!, cacheWidth: 320, fit: BoxFit.cover);
    if (error != null)
      return Center(
        child: TextButton(
          onPressed: () {
            setState(() => error = null);
            queue = queue.catchError((_) {}).then((_) => capture());
          },
          child: const Text('Retry cover'),
        ),
      );
    if (video != null)
      return Video(
        controller: video!,
        controls: NoVideoControls,
        fit: BoxFit.cover,
      );
    return const Center(child: PulseLoader());
  }
}
