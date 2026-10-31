import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'legendary_catalog.dart';

/// One ordinary hardware-compatible H264/AAC decoder. The Impeller image filter
/// unpacks synchronized RGB/matte from the same texture and emits premultiplied
/// alpha. There is no second mask decoder and no readback of video frames.
class PulseLegendaryGpuVideo extends StatefulWidget {
  const PulseLegendaryGpuVideo({
    super.key,
    required this.sku,
    required this.sound,
    required this.onComplete,
    required this.onStartupFailure,
    required this.onReady,
  });
  final String sku;
  final bool sound;
  final VoidCallback onComplete, onStartupFailure, onReady;
  @override
  State<PulseLegendaryGpuVideo> createState() => _PulseLegendaryGpuVideoState();
}

class _PulseLegendaryGpuVideoState extends State<PulseLegendaryGpuVideo>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _video;
  ui.FragmentShader? _shader;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _deadline;
  bool _ready = false, _done = false, _closed = false, _played = false;
  static Future<ui.FragmentProgram>? _program;
  PulseLegendaryGift get gift => pulseCinematicGifts[widget.sku]!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = Timer(const Duration(seconds: 12), _failed);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (!ui.ImageFilter.isShaderFilterSupported) {
        _failed();
        return;
      }
      final program = await (_program ??= ui.FragmentProgram.fromAsset(
        'shaders/gift_unpack.frag',
      ));
      if (_closed) return;
      _shader = program.fragmentShader();
      final p = Player(
        configuration: const PlayerConfiguration(title: 'Pulse legendary gift'),
      );
      _player = p;
      _video = VideoController(
        p,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      _subscriptions.add(p.stream.error.listen((_) => _failed()));
      _subscriptions.add(
        p.stream.completed.listen((done) {
          if (done) _complete();
        }),
      );
      _subscriptions.add(
        p.stream.position.listen((time) {
          if (time.inMilliseconds > 0) _played = true;
        }),
      );
      await p.setVolume(widget.sound ? 35 : 0);
      if (_closed) return;
      await p
          .open(
            Media('asset:///assets/gifts/${widget.sku}_packed.mp4'),
            play: false,
          )
          .timeout(const Duration(seconds: 8));
      if (_closed) return;
      _deadline?.cancel();
      _deadline = Timer(
        Duration(milliseconds: gift.durationMs + 10000),
        _complete,
      );
      setState(() => _ready = true);
      widget.onReady();
      _sync();
    } catch (_) {
      _failed();
    }
  }

  void _sync() {
    if (_closed || !_ready || _done) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (TickerMode.of(context) &&
        (life == null || life == AppLifecycleState.resumed)) {
      unawaited(_player?.play().catchError((_) {}));
    } else {
      unawaited(_player?.pause().catchError((_) {}));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();
  @override
  void didUpdateWidget(covariant PulseLegendaryGpuVideo old) {
    super.didUpdateWidget(old);
    if (old.sound != widget.sound)
      unawaited(_player?.setVolume(widget.sound ? 35 : 0).catchError((_) {}));
  }

  void _failed() {
    if (_done || _closed) return;
    _done = true;
    _deadline?.cancel();
    // Stop the failed decoder before any fallback can start audio.
    final p = _player;
    _player = null;
    unawaited(() async {
      try {
        await p?.dispose();
      } catch (_) {}
      if (!_closed) {
        if (_played) {
          widget.onComplete();
        } else {
          widget.onStartupFailure();
        }
      }
    }());
  }

  void _complete() {
    if (_done || _closed) return;
    _done = true;
    _deadline?.cancel();
    unawaited(_player?.stop().catchError((_) {}));
    widget.onComplete();
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _shader == null || _video == null)
      return const SizedBox.expand();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = bounds.maxWidth;
          final height = width / gift.aspectRatio;
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: width * 2,
                  maxWidth: width * 2,
                  minHeight: height,
                  maxHeight: height,
                  child: SizedBox(
                    width: width * 2,
                    height: height,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.shader(_shader!),
                      child: Video(
                        controller: _video!,
                        controls: NoVideoControls,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
