import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'avatar.dart';
import 'gifter_ranks.dart';
import 'gift_stories.dart';
import 'gift_visuals.dart';
import 'repository.dart' hide Row;

class PulseGiftStoryPlayer extends StatefulWidget {
  const PulseGiftStoryPlayer({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    required this.sound,
    this.fast = false,
  });
  final PulseRepository repo;
  final Map event;
  final bool sound, fast;
  final VoidCallback onComplete;
  @override
  State<PulseGiftStoryPlayer> createState() => _PulseGiftStoryPlayerState();
}

class _PulseGiftStoryPlayerState extends State<PulseGiftStoryPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController motion;
  Player? player;
  Timer? deadline;
  bool finished = false, opening = false, foreground = true, visible = true;
  String get sku => widget.event['sku'] as String;
  bool get story => ['rocket', 'castle', 'crown'].contains(sku);
  Duration get duration => Duration(
    milliseconds: sku == 'crown'
        ? 3000
        : sku == 'rocket'
        ? 7500
        : sku == 'castle'
        ? 8000
        : widget.fast
        ? 1200
        : 3800,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    motion = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) complete();
      })
      ..forward();
    deadline = Timer(duration + const Duration(seconds: 3), complete);
    if (widget.sound) unawaited(openAudio());
  }

  Future<void> openAudio() async {
    if (opening || player != null || finished) return;
    opening = true;
    try {
      final audio = Player(
        configuration: const PlayerConfiguration(title: 'Pulse gift sound'),
      );
      player = audio;
      await audio.setVolume(widget.sound ? 45 : 0);
      await audio.open(
        Media('asset:///assets/audio/gift_$sku.ogg'),
        play: false,
      );
      if (!mounted || finished) return;
      await audio.seek(
        Duration(
          milliseconds: (duration.inMilliseconds * motion.value).round(),
        ),
      );
      if (foreground && visible) await audio.play();
    } catch (_) {
      /* Visual story continues when sound is unavailable. */
    } finally {
      opening = false;
    }
  }

  @override
  void didUpdateWidget(covariant PulseGiftStoryPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sound && player == null) unawaited(openAudio());
    unawaited(
      player?.setVolume(widget.sound ? 45 : 0).catchError((_) {}) ??
          Future<void>.value(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.of(context);
    syncAudio();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    syncAudio();
  }

  void syncAudio() {
    final audio = player;
    if (audio == null || opening || finished) return;
    unawaited(() async {
      try {
        if (foreground && visible) {
          await audio.seek(
            Duration(
              milliseconds: (duration.inMilliseconds * motion.value).round(),
            ),
          );
          await audio.play();
        } else {
          await audio.pause();
        }
      } catch (_) {}
    }());
  }

  void complete() {
    if (!mounted || finished) return;
    finished = true;
    deadline?.cancel();
    widget.onComplete();
  }

  @override
  void dispose() {
    deadline?.cancel();
    motion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(player?.dispose().catchError((_) {}) ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: motion,
      builder: (_, __) {
        if (!story)
          return Center(
            child: SizedBox(
              width: 360,
              height: 400,
              child: PulseGiftEffect(
                repo: widget.repo,
                event: widget.event,
                fast: widget.fast,
                onComplete: complete,
              ),
            ),
          );
        final fade = ((1 - motion.value) * 12).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PulseGiftStoryScene(
                sku: sku,
                phase:
                    (motion.value * duration.inMilliseconds * .024).floor() /
                    (duration.inMilliseconds * .024),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 150,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xe0151d2b),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xffffd47c)),
                    ),
                    child: Row(
                      children: [
                        PulseAvatar(
                          repo: widget.repo,
                          path: widget.event['avatar_path'],
                          userId: widget.event['sender_id'],
                          name: widget.event['display_name'],
                          radius: 20,
                        ),
                        PulseRankBadge(
                          rank: (widget.event['gifter']?['rank'] as num? ?? 0)
                              .toInt(),
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${widget.event['is_test'] == true ? 'TEST · ' : ''}${widget.event['display_name']} sent ${widget.event['quantity']} × ${widget.event['title']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
