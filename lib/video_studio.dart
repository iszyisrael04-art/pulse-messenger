import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'media.dart';
import 'native_editor.dart';
import 'studio_model.dart';

class PulseVideoStudio extends StatefulWidget {
  const PulseVideoStudio({super.key, required this.file});
  final File file;
  @override
  State<PulseVideoStudio> createState() => _PulseVideoStudioState();
}

class _PulseVideoStudioState extends State<PulseVideoStudio>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration duration = Duration.zero, position = Duration.zero;
  RangeValues trim = const RangeValues(0, 1);
  bool mute = false, busy = false, ready = false, foreground = true;
  String tool = 'trim';
  String? error;
  double progress = 0;
  Uint8List? cover;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    open();
  }

  Future<void> open() async {
    try {
      MediaKit.ensureInitialized();
      final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
      );
      player = p;
      controller = VideoController(p);
      subscriptions.add(
        p.stream.duration.listen((v) {
          if (mounted && v.inMilliseconds > 0)
            setState(() {
              if (duration == Duration.zero)
                trim = RangeValues(0, v.inMilliseconds.toDouble());
              duration = v;
              ready = true;
            });
        }),
      );
      subscriptions.add(
        p.stream.position.listen((v) {
          if (!mounted) return;
          setState(() => position = v);
          if (v.inMilliseconds >= trim.end && duration != Duration.zero)
            p.pause();
        }),
      );
      subscriptions.add(
        p.stream.playing.listen((_) {
          if (mounted) setState(() {});
        }),
      );
      subscriptions.add(
        p.stream.error.listen((_) {
          if (mounted)
            setState(
              () => error =
                  'Preview could not play this video. Try a compatible MP4.',
            );
        }),
      );
      await PulseMedia.activate(p);
      await p.setVolume(100);
      await p.open(Media(widget.file.path));
    } catch (_) {
      if (mounted) setState(() => error = 'Video could not open.');
    }
  }

  String time(double ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
  Future<void> capture() async {
    try {
      await player?.pause();
      final bytes = await player?.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) throw StateError('No frame');
      if (mounted) setState(() => cover = bytes);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Play or seek to a frame, then try Set cover again.',
        );
    }
  }

  Future<void> save() async {
    if (!ready || busy || trim.end - trim.start < 250) return;
    await player!.pause();
    if (cover == null) await capture();
    if (cover == null) return;
    setState(() {
      busy = true;
      progress = 0;
      error = null;
    });
    File? exported;
    try {
      final changed =
          mute || trim.start > 50 || trim.end < duration.inMilliseconds - 100;
      File file = widget.file;
      if (changed) {
        final dir = await getTemporaryDirectory();
        exported = File('${dir.path}/pulse-video-${const Uuid().v4()}.mp4');
        file = await NativePulseEditor.export(
          widget.file,
          exported,
          trim.start.round(),
          trim.end.round(),
          mute,
          (v) {
            if (mounted) setState(() => progress = v);
          },
        );
      }
      if (mounted)
        Navigator.pop(context, PulseStudioResult(file, cover: cover));
    } catch (e) {
      if (exported != null && await exported.exists()) await exported.delete();
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) player?.pause();
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
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: const Color(0xff090b10),
      appBar: AppBar(
        backgroundColor: const Color(0xff090b10),
        foregroundColor: Colors.white,
        title: const Text('Pulse Studio'),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () {
                    setState(() {
                      trim = RangeValues(0, duration.inMilliseconds.toDouble());
                      mute = false;
                      cover = null;
                    });
                    player?.setVolume(100);
                    player?.seek(Duration.zero);
                  },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: controller == null
                        ? const Center(child: CircularProgressIndicator())
                        : Video(controller: controller!),
                  ),
                  SizedBox(
                    width: 76,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final entry in {
                          'trim': Icons.content_cut,
                          'mute': mute ? Icons.volume_off : Icons.volume_up,
                          'cover': Icons.image_outlined,
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                IconButton(
                                  tooltip: entry.key,
                                  onPressed: busy
                                      ? null
                                      : () {
                                          if (entry.key == 'mute') {
                                            setState(() => mute = !mute);
                                            player?.setVolume(mute ? 0 : 100);
                                          } else {
                                            setState(() => tool = entry.key);
                                          }
                                        },
                                  icon: Icon(
                                    entry.value,
                                    color:
                                        tool == entry.key ||
                                            entry.key == 'mute' && mute
                                        ? const Color(0xff52e0c4)
                                        : Colors.white,
                                  ),
                                ),
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (cover != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                cover!,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: const Color(0xff151922),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tool == 'trim') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          time(trim.start),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const Text(
                          'Trim video',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          time(trim.end),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: trim,
                      min: 0,
                      max: duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1,
                      onChanged: busy || !ready
                          ? null
                          : (v) {
                              if (v.end - v.start >= 250)
                                setState(() => trim = v);
                            },
                      onChangeEnd: (v) =>
                          player?.seek(Duration(milliseconds: v.start.round())),
                    ),
                    Text(
                      Platform.isAndroid
                          ? 'Android trims align to video keyframes.'
                          : 'Precise native Windows export.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (tool == 'cover') ...[
                    Slider(
                      value: position.inMilliseconds
                          .toDouble()
                          .clamp(0, duration.inMilliseconds.toDouble())
                          .toDouble(),
                      max: duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1,
                      onChanged: busy || !ready
                          ? null
                          : (v) =>
                                player?.seek(Duration(milliseconds: v.round())),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : capture,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Set cover from current frame'),
                    ),
                  ],
                  if (busy) ...[
                    LinearProgressIndicator(value: progress),
                    Text(
                      'Exporting ${(progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed: NativePulseEditor.cancel,
                      child: const Text('Cancel export'),
                    ),
                  ],
                  if (!busy)
                    Row(
                      children: [
                        IconButton(
                          tooltip: player?.state.playing == true
                              ? 'Pause'
                              : 'Play selected range',
                          onPressed: !ready
                              ? null
                              : () async {
                                  if (position.inMilliseconds >= trim.end ||
                                      position.inMilliseconds < trim.start)
                                    await player?.seek(
                                      Duration(
                                        milliseconds: trim.start.round(),
                                      ),
                                    );
                                  await player?.playOrPause();
                                },
                          icon: Icon(
                            player?.state.playing == true
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: ready ? save : null,
                            icon: const Icon(Icons.check),
                            label: const Text('Use edited video'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
