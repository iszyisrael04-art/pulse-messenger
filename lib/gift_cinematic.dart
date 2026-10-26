import 'gift_assets.dart';
import 'gift_story_player.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'avatar.dart';
import 'gift_visuals.dart';
import 'gifter_ranks.dart';
import 'repository.dart' hide Row;

/// Rendered original 3D scenes keep LIVE's CPU and camera budget available.
/// Every path has a deadline so a failed decoder cannot hold the gift queue.
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
  Widget build(BuildContext context) {
    if (['wizard_filter', 'witch_filter'].contains(event['sku']) && event['preview_only'] != true) {
      return _FilterGiftNotice(repo: repo, event: event, onComplete: onComplete);
    }
    if (['rocket', 'castle', 'crown'].contains(event['sku']) &&
        !MediaQuery.disableAnimationsOf(context)) {
      return PulseGiftStoryPlayer(
        repo: repo,
        event: event,
        sound: sound,
        onComplete: onComplete,
      );
    }
    if (pulseGiftMovies.containsKey(event['sku']) &&
        !MediaQuery.disableAnimationsOf(context)) {
      return _AssetCinematic(
        repo: repo,
        event: event,
        sound: sound,
        onComplete: onComplete,
      );
    }
    if (!MediaQuery.disableAnimationsOf(context)) {
      return PulseGiftStoryPlayer(
        repo: repo,
        event: event,
        sound: sound,
        fast: fast,
        onComplete: onComplete,
      );
    }
    return Center(
      child: SizedBox(
        width: 360,
        height: 400,
        child: PulseGiftEffect(
          repo: repo,
          event: event,
          fast: fast,
          onComplete: onComplete,
        ),
      ),
    );
  }
}

class _AssetCinematic extends StatefulWidget {
  const _AssetCinematic({
    required this.repo,
    required this.event,
    required this.sound,
    required this.onComplete,
  });
  final PulseRepository repo;
  final Map event;
  final bool sound;
  final VoidCallback onComplete;
  @override
  State<_AssetCinematic> createState() => _AssetCinematicState();
}

class _AssetCinematicState extends State<_AssetCinematic>
    with WidgetsBindingObserver {
  late final Player player;
  late final VideoController video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? deadline;
  bool finished = false, failed = false;
  bool foreground = true, routeVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    player = Player(
      configuration: const PlayerConfiguration(title: 'Pulse gift'),
    );
    video = VideoController(player);
    subscriptions.add(
      player.stream.completed.listen((done) {
        if (done) complete();
      }),
    );
    subscriptions.add(player.stream.error.listen((_) => fallback()));
    deadline = Timer(const Duration(seconds: 10), complete);
    unawaited(start());
  }

  Future<void> start() async {
    try {
      await player.setVolume(widget.sound ? 45 : 0);
      if (!mounted) return;
      await player.open(
        Media(
          'asset:///assets/gifts/cinema_${pulseGiftMovies[widget.event['sku']]}.mp4',
        ),
        play: foreground && routeVisible,
      );
    } catch (_) {
      fallback();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeVisible = TickerMode.of(context);
    unawaited(syncPlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    unawaited(syncPlayback());
  }

  Future<void> syncPlayback() async {
    try {
      if (foreground && routeVisible && !failed && !finished) {
        await player.play();
      } else {
        await player.pause();
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _AssetCinematic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sound != widget.sound) {
      unawaited(player.setVolume(widget.sound ? 45 : 0).catchError((_) {}));
    }
  }

  void fallback() {
    if (!mounted || finished || failed) return;
    unawaited(player.stop().catchError((_) {}));
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
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: SizedBox(
          width: 360,
          height: 400,
          child: PulseGiftEffect(
            repo: widget.repo,
            event: widget.event,
            onComplete: complete,
          ),
        ),
      );
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (_, bounds) => Video(
              controller: video,
              controls: NoVideoControls,
              fit: bounds.maxWidth / bounds.maxHeight > .8
                  ? BoxFit.contain
                  : BoxFit.cover,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black38, Colors.transparent, Colors.black54],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 150,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xdd151d17),
                  border: Border.all(color: const Color(0xffffd684)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    PulseAvatar(
                      repo: widget.repo,
                      path: widget.event['avatar_path'],
                      userId: widget.event['sender_id'],
                      name: widget.event['display_name'],
                      radius: 22,
                    ),
                    PulseRankBadge(
                      rank: (widget.event['gifter']?['rank'] as num? ?? 0)
                          .toInt(),
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.event['is_test'] == true ? 'TEST · ' : ''}${widget.event['display_name']} sent ${widget.event['quantity']} × ${widget.event['sku'] == 'galaxy' ? 'Pulse Universe' : widget.event['title'] ?? widget.event['sku']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
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
  }
}

class _FilterGiftNotice extends StatefulWidget {
  const _FilterGiftNotice({required this.repo, required this.event, required this.onComplete});
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  @override
  State<_FilterGiftNotice> createState() => _FilterGiftNoticeState();
}
class _FilterGiftNoticeState extends State<_FilterGiftNotice> {
  Timer? timer;
  @override
  void initState() { super.initState(); timer = Timer(const Duration(seconds: 3), widget.onComplete); }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, .6),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseAvatar(repo: widget.repo, path: widget.event['avatar_path'], userId: widget.event['sender_id'], name: widget.event['display_name'] ?? 'Viewer', radius: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text('${widget.event['display_name'] ?? 'Viewer'} sent ${widget.event['quantity'] ?? 1} × ${widget.event['title'] ?? 'Magic head filter'}',
              style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );
}
