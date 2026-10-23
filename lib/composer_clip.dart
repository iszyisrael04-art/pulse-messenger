import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'media.dart';

/// Local preview: never uploads or records a view and never autoplays.
class PulseComposerClip extends StatefulWidget {
  const PulseComposerClip({super.key, required this.file, this.cover});
  final File file;
  final Uint8List? cover;
  @override
  State<PulseComposerClip> createState() => _PulseComposerClipState();
}

class _PulseComposerClipState extends State<PulseComposerClip>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? video;
  StreamSubscription<bool>? playingSubscription;
  bool loading = false, playing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> toggle() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (player == null) {
        MediaKit.ensureInitialized();
        final p = Player(
          configuration: const PlayerConfiguration(bufferSize: 4 * 1024 * 1024),
        );
        player = p;
        video = VideoController(p);
        playingSubscription = p.stream.playing.listen((value) {
          if (mounted) setState(() => playing = value);
        });
        setState(() {});
        await p
            .open(Media(widget.file.path), play: false)
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted) return;
      await PulseMedia.activate(player!);
      await player!.playOrPause();
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Preview unavailable. You can still edit in Studio.',
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void deactivate() {
    player?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playingSubscription?.cancel();
    final p = player;
    if (PulseMedia.active == p) PulseMedia.active = null;
    if (p != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        p.dispose();
      });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (widget.cover != null)
        Image.memory(widget.cover!, fit: BoxFit.contain, cacheWidth: 1100),
      if (video != null)
        Video(
          controller: video!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      Center(
        child: loading
            ? const CircularProgressIndicator()
            : IconButton.filledTonal(
                tooltip: playing ? 'Pause preview' : 'Play preview',
                iconSize: 40,
                onPressed: toggle,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
      ),
      if (error != null)
        Positioned(
          left: 16,
          right: 16,
          bottom: 70,
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
    ],
  );
}
