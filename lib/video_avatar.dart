import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One silent player for a large, visible profile portrait; chat rows use posters.
class PulseVideoAvatar extends StatefulWidget {
  const PulseVideoAvatar({super.key, required this.url, required this.poster});
  final String url;
  final Widget poster;
  @override
  State<PulseVideoAvatar> createState() => _PulseVideoAvatarState();
}

class _PulseVideoAvatarState extends State<PulseVideoAvatar>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  Timer? visibility;
  StreamSubscription<Duration>? position;
  StreamSubscription<String>? errors;
  bool foreground = true, failed = false, opening = false, playing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    visibility = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => updatePlayback(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => updatePlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updatePlayback();
  }

  Future<void> updatePlayback() async {
    if (!mounted || opening || failed) return;
    final box = context.findRenderObject();
    final visible =
        foreground &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context) &&
        ModalRoute.of(context)?.isCurrent != false &&
        box is RenderBox &&
        box.attached &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).overlaps(
          Offset.zero & MediaQuery.sizeOf(context),
        );
    if (visible && player == null) {
      opening = true;
      try {
        MediaKit.ensureInitialized();
        final own = Player(
          configuration: const PlayerConfiguration(bufferSize: 2 * 1024 * 1024),
        );
        player = own;
        controller = VideoController(own);
        errors = own.stream.error.listen((_) {
          if (mounted) {
            setState(() => failed = true);
            unawaited(own.pause().catchError((_) {}));
          }
        });
        position = own.stream.position.listen((value) {
          if (mounted && value.inMilliseconds >= 5000)
            unawaited(own.seek(Duration.zero).catchError((_) {}));
        });
        await own.setVolume(0);
        await own.setPlaylistMode(PlaylistMode.loop);
        await own.open(Media(widget.url), play: false);
        if (mounted) setState(() {});
      } catch (_) {
        if (mounted) setState(() => failed = true);
      } finally {
        opening = false;
      }
      if (mounted) updatePlayback();
      return;
    }
    if (player != null && visible != playing) {
      playing = visible;
      try {
        if (visible) {
          await player!.play();
        } else {
          await player!.pause();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    visibility?.cancel();
    position?.cancel();
    errors?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final old = player;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => failed || controller == null
      ? widget.poster
      : Video(
          controller: controller!,
          fit: BoxFit.cover,
          controls: NoVideoControls,
        );
}
