import 'appearance.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'media.dart';

class SocialSelectionPreview extends StatefulWidget {
  const SocialSelectionPreview({
    super.key,
    required this.file,
    required this.video,
  });
  final File file;
  final bool video;
  @override
  State<SocialSelectionPreview> createState() => _SocialSelectionPreviewState();
}

class _SocialSelectionPreviewState extends State<SocialSelectionPreview>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  bool ready = false, busy = false;
  String? error;
  StreamSubscription<String>? errors;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.video)
      open();
    else
      ready = true;
  }

  Future<void> open() async {
    try {
      MediaKit.ensureInitialized();
      final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
      );
      player = p;
      controller = VideoController(p);
      errors = p.stream.error.listen((_) {
        if (mounted)
          setState(
            () => error =
                'This video cannot be previewed. Choose a compatible MP4.',
          );
      });
      await PulseMedia.pauseAll();
      await p.open(Media(widget.file.path), play: false);
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted)
        setState(() => error = 'Preview unavailable. Choose another file.');
    }
  }

  Future<void> accept() async {
    setState(() => busy = true);
    try {
      Uint8List? cover;
      if (player != null) {
        await player!.pause();
        cover = await player!
            .screenshot(format: 'image/jpeg')
            .timeout(const Duration(seconds: 5));
        if (cover == null || cover.isEmpty) {
          if (mounted)
            setState(
              () =>
                  error = 'Wait for the video frame, then tap Use media again.',
            );
          return;
        }
      }
      if (mounted) Navigator.pop(context, (accepted: true, cover: cover));
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not capture the cover. Try playing and pausing first.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    errors?.cancel();
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preview media')),
    body: Column(
      children: [
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(
          child: widget.video
              ? controller == null
                    ? const Center(child: PulseLoader())
                    : Video(controller: controller!)
              : Image.file(
                  widget.file,
                  cacheWidth: 960,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Text('Photo could not load')),
                ),
        ),
        if (widget.video)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Play and pause on the frame you want as your cover.'),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton.icon(
            onPressed: !ready || busy ? null : accept,
            icon: const Icon(Icons.check),
            label: Text(busy ? 'Preparing cover…' : 'Use media'),
          ),
        ),
      ],
    ),
  );
}
