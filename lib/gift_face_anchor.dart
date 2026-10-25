import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'gift_visuals.dart';

class PulseFaceAnchor {
  const PulseFaceAnchor(this.bounds, this.frame, this.roll);
  final Rect bounds; // Normalized, unmirrored image coordinates.
  final Size frame;
  final double roll;
}

Rect pulseFaceOnVideo(
  PulseFaceAnchor face,
  Size viewport, {
  bool mirror = false,
}) {
  final fitted = applyBoxFit(BoxFit.contain, face.frame, viewport).destination;
  final box = Alignment.center.inscribe(fitted, Offset.zero & viewport);
  final left = mirror ? 1 - face.bounds.right : face.bounds.left;
  return Rect.fromLTWH(
    box.left + left * box.width,
    box.top + face.bounds.top * box.height,
    face.bounds.width * box.width,
    face.bounds.height * box.height,
  );
}

typedef _DetectC = Int32 Function(Pointer<Utf16>, Pointer<Double>);
typedef _DetectDart = int Function(Pointer<Utf16>, Pointer<Double>);
List<double>? _windowsFace(String path) {
  final input = path.toNativeUtf16(), output = calloc<Double>(5);
  try {
    final call = DynamicLibrary.open(
      'pulse_editor.dll',
    ).lookupFunction<_DetectC, _DetectDart>('pulse_gift_face');
    if (call(input, output) != 1) return null;
    return [for (var i = 0; i < 5; i++) output[i]];
  } finally {
    calloc.free(input);
    calloc.free(output);
  }
}

/// Throttled snapshots only while a gifted crown is visible. Images and face
/// boxes never leave this device, and temporary WebRTC snapshots are removed.
bool _snapshotBusy = false;
Future<PulseFaceAnchor?> pulseSampleFace(lk.VideoTrack track) async {
  if (_snapshotBusy ||
      !(Platform.isAndroid || Platform.isIOS || Platform.isWindows))
    return null;
  const channel = MethodChannel('pulse/gift_faces');
  File? temporary;
  ui.Codec? codec;
  ui.Image? image;
  var abandoned = false;
  try {
    final dir = await getTemporaryDirectory();
    final snapshot = File('${dir.path}/captureFrame.png');
    temporary = snapshot;
    _snapshotBusy = true;
    final capture = track.mediaStreamTrack.captureFrame();
    unawaited(
      capture.then<void>(
        (_) async {
          _snapshotBusy = false;
          if (abandoned) {
            try {
              await snapshot.delete();
            } catch (_) {}
          }
        },
        onError: (Object _, StackTrace stack) {
          _snapshotBusy = false;
        },
      ),
    );
    final bytes = (await capture.timeout(
      const Duration(seconds: 1),
    )).asUint8List();
    codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
    image = (await codec.getNextFrame()).image;
    final frame = Size(image.width.toDouble(), image.height.toDouble());
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) return null;
    final png = Uint8List.sublistView(encoded);
    List<dynamic>? values;
    if (Platform.isWindows) {
      // WinRT runs on a worker isolate; it reads the same disposable snapshot.
      await temporary.writeAsBytes(png, flush: true);
      final path = temporary.path;
      values = await Isolate.run(
        () => _windowsFace(path),
      ).timeout(const Duration(seconds: 2));
    } else if (Platform.isAndroid || Platform.isIOS) {
      values = await channel
          .invokeListMethod<dynamic>('detect', {'bytes': png})
          .timeout(const Duration(seconds: 1));
    }
    if (values == null ||
        values.length != 5 ||
        values.any((v) => v is! num || !v.isFinite))
      return null;
    final r = Rect.fromLTWH(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
      (values[2] as num).toDouble(),
      (values[3] as num).toDouble(),
    ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
    if (r.width < .05 || r.height < .05) return null;
    return PulseFaceAnchor(r, frame, (values[4] as num).toDouble());
  } catch (_) {
    return null;
  } finally {
    abandoned = true;
    image?.dispose();
    codec?.dispose();
    if (temporary != null) {
      try {
        await temporary.delete();
      } catch (_) {}
    }
  }
}

class PulseHeadCrown extends StatefulWidget {
  const PulseHeadCrown({
    super.key,
    required this.until,
    required this.sample,
    required this.child,
    this.mirror = false,
  });
  final DateTime until;
  final Future<PulseFaceAnchor?> Function() sample;
  final Widget child;
  final bool mirror;
  @override
  State<PulseHeadCrown> createState() => _PulseHeadCrownState();
}

class _PulseHeadCrownState extends State<PulseHeadCrown>
    with WidgetsBindingObserver {
  PulseFaceAnchor? anchor;
  Timer? timer, expiry;
  bool sampling = false, foreground = true, visible = true, expired = false;
  bool get active =>
      !expired && widget.until.isAfter(DateTime.now()) && foreground && visible;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.of(context);
    schedule();
  }

  @override
  void didUpdateWidget(covariant PulseHeadCrown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  void schedule() {
    expired = !widget.until.isAfter(DateTime.now());
    timer?.cancel();
    expiry?.cancel();
    if (!active) {
      anchor = null;
      if (mounted) setState(() {});
      return;
    }
    expiry = Timer(widget.until.difference(DateTime.now()), () {
      timer?.cancel();
      expired = true;
      if (mounted) setState(() => anchor = null);
    });
    timer = Timer.periodic(const Duration(milliseconds: 350), (_) => sample());
    unawaited(sample());
  }

  Future<void> sample() async {
    if (sampling || !active) return;
    sampling = true;
    try {
      final next = await widget.sample();
      if (mounted && active) setState(() => anchor = next);
    } catch (_) {
      if (mounted) setState(() => anchor = null);
    } finally {
      sampling = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, bounds) {
      final a = anchor;
      Rect? crown;
      if (a != null && active) {
        final face = pulseFaceOnVideo(a, bounds.biggest, mirror: widget.mirror);
        final width = face.width * 1.38;
        crown = Rect.fromCenter(
          center: Offset(face.center.dx, face.top - face.width * .10),
          width: width,
          height: width * .62,
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (crown != null)
            AnimatedPositioned(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: crown.left,
              top: crown.top,
              width: crown.width,
              height: crown.height,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: (a!.roll * (widget.mirror ? -1 : 1)).clamp(
                    -math.pi / 3,
                    math.pi / 3,
                  ),
                  child: const PulseGiftModel(sku: 'crown', phase: .1),
                ),
              ),
            ),
        ],
      );
    },
  );
}
