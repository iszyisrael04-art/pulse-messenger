import 'legendary_gpu_overlay.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'avatar.dart';
import 'gift_visuals.dart';
import 'legendary_catalog.dart';
import 'repository.dart' hide Row;

/// Cache compressed bytes only, never a frame sequence or a second video decoder.
class PulseLegendaryBytes {
  static final _cache = <String, Uint8List>{};
  static int _size = 0;
  static const budget = 8 * 1024 * 1024;
  static Future<Uint8List> load(String sku) async {
    if (!pulseCinematicGifts.containsKey(sku))
      throw const FormatException('Unknown gift');
    final hit = _cache.remove(sku);
    if (hit != null) {
      _cache[sku] = hit;
      return hit;
    }
    final data = await rootBundle.load('assets/gifts/$sku.webp');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    while (_cache.isNotEmpty && _size + bytes.length > budget) {
      _size -= _cache.remove(_cache.keys.first)!.length;
    }
    if (bytes.length <= budget) {
      _cache[sku] = bytes;
      _size += bytes.length;
    }
    return bytes;
  }
}

/// The precomputed alpha is composited by Flutter's GPU. CPU/WebP decoding is
/// the portable fallback to unsupported native alpha-video formats. Inference
/// and matting never run on the phone. At most one frame is decoded in flight.
class _PulseLegendaryPortableOverlay extends StatefulWidget {
  const _PulseLegendaryPortableOverlay({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    this.sound = true,
  });
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  final bool sound;
  @override
  State<_PulseLegendaryPortableOverlay> createState() =>
      __PulseLegendaryPortableOverlayState();
}

class __PulseLegendaryPortableOverlayState
    extends State<_PulseLegendaryPortableOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ui.Codec? _codec;
  ui.Image? _frame;
  Player? _audio;
  StreamSubscription<Duration>? _positions;
  late final Ticker _ticker = createTicker(_tick);
  final _clock = Stopwatch();
  Timer? _deadline;
  bool _active = false,
      _ready = false,
      _loading = false,
      _decoding = false,
      _disposed = false,
      _done = false,
      _failed = false;
  int _frameEnd = 0, _decoded = 0, _anchor = 0, _anchorClock = 0;
  bool _hasAnchor = false;
  String get sku => widget.event['sku'].toString();
  PulseLegendaryGift get gift => pulseCinematicGifts[sku]!;
  int get elapsed => _hasAnchor
      ? (_anchor + _clock.elapsedMilliseconds - _anchorClock).clamp(
          0,
          gift.durationMs,
        )
      : _clock.elapsedMilliseconds;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = Timer(const Duration(seconds: 15), _complete);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading) {
      _loading = true;
      unawaited(_load());
    }
    _sync();
  }

  Future<void> _load() async {
    ui.Codec? codec;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _failed = true;
        _ready = true;
        _deadline?.cancel();
        _deadline = Timer(const Duration(seconds: 3), _complete);
        if (mounted) setState(() {});
        return;
      }
      final bytes = await PulseLegendaryBytes.load(sku);
      if (_disposed) return;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 480,
        allowUpscaling: false,
      );
      if (_disposed) {
        codec.dispose();
        return;
      }
      final first = await codec.getNextFrame();
      if (_disposed) {
        first.image.dispose();
        codec.dispose();
        return;
      }
      _codec = codec;
      _frame = first.image;
      _decoded = 1;
      _frameEnd = first.duration.inMilliseconds;
      try {
        final audio = Player(
          configuration: const PlayerConfiguration(
            title: 'Pulse legendary gift',
          ),
        );
        _audio = audio;
        await audio.setVolume(widget.sound ? 35 : 0);
        if (_disposed) return;
        await audio
            .open(Media('asset:///assets/gifts/$sku.m4a'), play: false)
            .timeout(const Duration(seconds: 5));
        if (_disposed) return;
        _positions = audio.stream.position.listen((p) {
          if (_active && !_disposed) {
            _anchor = p.inMilliseconds;
            _anchorClock = _clock.elapsedMilliseconds;
            _hasAnchor = true;
          }
        });
      } catch (_) {
        final audio = _audio;
        _audio = null;
        unawaited(audio?.dispose());
      }
      if (_disposed) return;
      _ready = true;
      _deadline?.cancel();
      _deadline = Timer(
        Duration(milliseconds: gift.durationMs + 10000),
        _complete,
      );
      _ticker.start();
      _sync();
      setState(() {});
    } catch (_) {
      if (_codec == null) codec?.dispose();
      if (!_disposed) {
        _failed = true;
        _ready = true;
        _deadline?.cancel();
        _deadline = Timer(const Duration(seconds: 3), _complete);
        setState(() {});
      }
    }
  }

  void _sync() {
    if (_disposed || _done) return;
    final life = WidgetsBinding.instance.lifecycleState;
    final shouldPlay =
        _ready &&
        !_failed &&
        TickerMode.of(context) &&
        (life == null || life == AppLifecycleState.resumed);
    if (shouldPlay == _active) return;
    _active = shouldPlay;
    if (_active) {
      _clock.start();
      unawaited(_audio?.play().catchError((_) {}));
    } else {
      _clock.stop();
      unawaited(_audio?.pause().catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();
  void _tick(Duration _) {
    if (!_active || _done || _disposed) return;
    final time = elapsed;
    if (time >= gift.durationMs) {
      _complete();
      return;
    }
    if (time >= _frameEnd && !_decoding && _decoded < (_codec?.frameCount ?? 0))
      unawaited(_next(time));
    if (time < 250 || time > gift.durationMs - 300) setState(() {});
  }

  Future<void> _next(int time) async {
    final codec = _codec;
    if (codec == null || _decoding) return;
    _decoding = true;
    ui.FrameInfo? next;
    try {
      var skipped = 0;
      do {
        next?.image.dispose();
        next = await codec.getNextFrame();
        _decoded++;
        _frameEnd += next.duration.inMilliseconds;
      } while (!_disposed &&
          _active &&
          _frameEnd < elapsed &&
          _decoded < codec.frameCount &&
          ++skipped < 3);
      if (_disposed) {
        next.image.dispose();
        return;
      }
      final old = _frame;
      setState(() => _frame = next!.image);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old?.dispose();
      });
    } catch (_) {
      if (!_disposed) {
        _failed = true;
        _complete();
      }
    } finally {
      _decoding = false;
      if (_disposed) {
        codec.dispose();
      }
    }
  }

  void _complete() {
    if (_done || _disposed) return;
    _done = true;
    _clock.stop();
    _ticker.stop();
    _deadline?.cancel();
    unawaited(_audio?.stop().catchError((_) {}));
    widget.onComplete();
  }

  @override
  void didUpdateWidget(covariant _PulseLegendaryPortableOverlay old) {
    super.didUpdateWidget(old);
    if (old.sound != widget.sound)
      unawaited(_audio?.setVolume(widget.sound ? 35 : 0).catchError((_) {}));
    // The enclosing combo key is stable: updated counts never restart the codec/audio.
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    _ticker.dispose();
    _clock.stop();
    unawaited(_positions?.cancel());
    unawaited(_audio?.dispose());
    if (!_decoding) _codec?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _ready && !_failed ? elapsed : 250;
    final noticeOpacity =
        (t / 220).clamp(0.0, 1.0) *
        ((gift.durationMs - t) / 240).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_frame != null && !_failed)
            RepaintBoundary(
              child: RawImage(
                image: _frame,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          Transform.translate(
            offset: Offset(-24 * (1 - noticeOpacity), 0),
            child: Opacity(
              opacity: noticeOpacity,
              child: PulseGiftNotice(
                name: widget.event['display_name']?.toString() ?? 'Viewer',
                title: gift.title,
                quantity:
                    ((widget.event['combo_quantity'] ??
                                    widget.event['quantity'])
                                as num? ??
                            1)
                        .toInt(),
                coins: (widget.event['coins'] as num?)?.toInt() ?? gift.coins,
                alignment: const Alignment(-1, -.66),
                test: widget.event['is_test'] == true,
                avatar: PulseAvatar(
                  repo: widget.repo,
                  path: widget.event['avatar_path'],
                  userId: widget.event['sender_id'],
                  name: widget.event['display_name'],
                  radius: 19,
                ),
                gift: PulseGiftModel(sku: sku),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prefer a single hardware video decoder and GPU matte unpacking on Impeller.
/// Windows/Skia and unsupported devices use the portable alpha codec instead.
class PulseLegendaryOverlay extends StatefulWidget {
  const PulseLegendaryOverlay({
    super.key,
    required this.repo,
    required this.event,
    required this.onComplete,
    this.sound = true,
  });
  final PulseRepository repo;
  final Map event;
  final VoidCallback onComplete;
  final bool sound;
  @override
  State<PulseLegendaryOverlay> createState() => _PulseLegendaryOverlayState();
}

class _PulseLegendaryOverlayState extends State<PulseLegendaryOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _notice = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: pulseCinematicGifts[widget.event['sku']]!.durationMs,
    ),
  );
  bool _portable = false, _gpuReady = false;
  static const forcePortable = bool.fromEnvironment('PULSE_GIFT_PORTABLE');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    if (!_gpuReady) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (TickerMode.of(context) &&
        (life == null || life == AppLifecycleState.resumed)) {
      if (!_notice.isCompleted) _notice.forward();
    } else {
      _notice.stop();
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_portable ||
        forcePortable ||
        !ui.ImageFilter.isShaderFilterSupported ||
        MediaQuery.disableAnimationsOf(context)) {
      return _PulseLegendaryPortableOverlay(
        repo: widget.repo,
        event: widget.event,
        onComplete: widget.onComplete,
        sound: widget.sound,
      );
    }
    final sku = widget.event['sku'].toString(),
        gift = pulseCinematicGifts[widget.event['sku']]!;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          PulseLegendaryGpuVideo(
            sku: sku,
            sound: widget.sound,
            onComplete: widget.onComplete,
            onReady: () {
              _gpuReady = true;
              _sync();
            },
            onStartupFailure: () {
              if (mounted) setState(() => _portable = true);
            },
          ),
          AnimatedBuilder(
            animation: _notice,
            builder: (context, child) {
              final ms = _notice.value * gift.durationMs;
              final opacity =
                  (ms / 220).clamp(0.0, 1.0) *
                  ((gift.durationMs - ms) / 240).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(-24 * (1 - opacity), 0),
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: PulseGiftNotice(
              name: widget.event['display_name']?.toString() ?? 'Viewer',
              title: gift.title,
              quantity:
                  ((widget.event['combo_quantity'] ?? widget.event['quantity'])
                              as num? ??
                          1)
                      .toInt(),
              coins: (widget.event['coins'] as num?)?.toInt() ?? gift.coins,
              alignment: const Alignment(-1, -.66),
              test: widget.event['is_test'] == true,
              avatar: PulseAvatar(
                repo: widget.repo,
                path: widget.event['avatar_path'],
                userId: widget.event['sender_id'],
                name: widget.event['display_name'],
                radius: 19,
              ),
              gift: PulseGiftModel(sku: sku),
            ),
          ),
        ],
      ),
    );
  }
}
