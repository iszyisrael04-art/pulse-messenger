import 'legendary_overlay.dart';
import 'legendary_catalog.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'avatar.dart';
import 'gift_assets.dart';
import 'gift_visuals.dart';
import 'repository.dart' hide Row;

/// Notification-only gifts or short, licensed wildlife MP4s. No 3D/effects.
class _PulseClassicGiftPresentation extends StatefulWidget {
  const _PulseClassicGiftPresentation({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    this.sound = true,
    this.fast = false,
  });
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  final bool sound, fast;
  @override
  State<_PulseClassicGiftPresentation> createState() =>
      __PulseClassicGiftPresentationState();
}

class __PulseClassicGiftPresentationState
    extends State<_PulseClassicGiftPresentation>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? deadline;
  bool foreground = true,
      routeVisible = true,
      finished = false,
      failed = false,
      started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeVisible = TickerMode.of(context);
    if (!started) {
      started = true;
      if (pulseGiftHasVideo(widget.event) &&
          !MediaQuery.disableAnimationsOf(context)) {
        player = Player(
          configuration: const PlayerConfiguration(
            title: 'Pulse wildlife gift',
          ),
        );
        controller = VideoController(player!);
        subscriptions.add(
          player!.stream.completed.listen((done) {
            if (done) complete();
          }),
        );
        subscriptions.add(player!.stream.error.listen((_) => fallback()));
        deadline = Timer(const Duration(seconds: 8), complete);
        unawaited(start());
      } else {
        deadline = Timer(
          Duration(milliseconds: widget.fast ? 1500 : 3000),
          complete,
        );
      }
    }
    unawaited(syncPlayback());
  }

  Future<void> start() async {
    try {
      await player!.setVolume(widget.sound ? 45 : 0);
      if (!mounted || finished) return;
      await player!.open(
        Media(
          'asset:///assets/gifts/wildlife_${pulseGiftMovies[widget.event['sku']]}.mp4',
        ),
        play: foreground && routeVisible,
      );
    } catch (_) {
      fallback();
    }
  }

  Future<void> syncPlayback() async {
    try {
      if (foreground && routeVisible && !finished && !failed) {
        await player?.play();
      } else {
        await player?.pause();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    unawaited(syncPlayback());
  }

  @override
  void didUpdateWidget(covariant _PulseClassicGiftPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (player == null &&
        oldWidget.event['combo_quantity'] != widget.event['combo_quantity']) {
      deadline?.cancel();
      deadline = Timer(const Duration(seconds: 3), complete);
    }
    if (oldWidget.sound != widget.sound)
      unawaited(player?.setVolume(widget.sound ? 45 : 0).catchError((_) {}));
  }

  void fallback() {
    if (!mounted || finished || failed) return;
    unawaited(player?.stop().catchError((_) {}));
    deadline?.cancel();
    deadline = Timer(const Duration(seconds: 2), complete);
    setState(() => failed = true);
  }

  void complete() {
    if (!mounted || finished) return;
    finished = true;
    deadline?.cancel();
    widget.onComplete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    deadline?.cancel();
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sku = widget.event['sku']?.toString() ?? '';
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && !failed) ...[
            // Preserve the whole wildlife frame. No replacement background or filter.
            Center(
              child: Video(
                controller: controller!,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 80,
              child: Text(
                '${pulseGiftCredits[sku]?.split('\n').first ?? ''}\nTrimmed footage · Shop → Footage credits',
                maxLines: 3,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
          PulseGiftNotice(
            name: widget.event['display_name']?.toString() ?? 'Viewer',
            title: widget.event['title']?.toString() ?? sku,
            quantity:
                ((widget.event['combo_quantity'] ?? widget.event['quantity'])
                            as num? ??
                        1)
                    .toInt(),
            test: widget.event['is_test'] == true,
            coins: pulseCinematicGifts[widget.event['sku']]?.coins,
            avatar: PulseAvatar(
              repo: widget.repo,
              path: widget.event['avatar_path'],
              userId: widget.event['sender_id'],
              name: widget.event['display_name'],
              radius: 19,
            ),
            gift: PulseGiftModel(sku: sku),
          ),
        ],
      ),
    );
  }
}

/// Preserve classic gifts while routing configured legendary gifts to real alpha compositing.
class PulseLiveGiftPresentation extends StatelessWidget {
  const PulseLiveGiftPresentation({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    this.sound = true,
    this.fast = false,
  });
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  final bool sound, fast;
  @override
  Widget build(BuildContext context) => pulseLegendaryForEvent(event) != null
      ? PulseLegendaryOverlay(
          repo: repo,
          event: event,
          onComplete: onComplete,
          sound: sound,
        )
      : _PulseClassicGiftPresentation(
          repo: repo,
          event: event,
          onComplete: onComplete,
          sound: sound,
          fast: fast,
        );
}
