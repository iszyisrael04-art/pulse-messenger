import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'media.dart';
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
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return Image.network(
        s.data!,
        fit: BoxFit.contain,
        cacheWidth: 960,
        loadingBuilder: (_, child, loading) => loading == null
            ? child
            : const Center(child: CircularProgressIndicator()),
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
  });
  final SocialStore store;
  final bool recordView;
  final String postId, path;
  @override
  State<SocialInlineVideo> createState() => _SocialInlineVideoState();
}

class _SocialInlineVideoState extends State<SocialInlineVideo>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  String? error;
  bool loading = false, viewed = false;
  final subscriptions = <StreamSubscription<dynamic>>[];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> play() async {
    if (loading) return;
    setState(() {
      loading = true;
    });
    try {
      if (player != null && error == null) {
        await PulseMedia.activate(player!);
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
      if (!mounted) return;
      MediaKit.ensureInitialized();
      player = Player(
        configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
      );
      controller = VideoController(player!);
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
      await PulseMedia.activate(player!);
      await player!.open(Media(url));
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) {
      s.cancel();
    }
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
            ? Video(controller: controller!)
            : Center(
                child: loading
                    ? const CircularProgressIndicator()
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
