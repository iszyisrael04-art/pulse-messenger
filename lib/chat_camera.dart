import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'media.dart';

class PulseCapture {
  const PulseCapture(
    this.file, {
    required this.video,
    this.round = false,
    this.duration = 0,
  });
  final File file;
  final bool video, round;
  final int duration;
}

/// Tap for the camera, hold and swipe up for a locked video-note recorder.
class PulseCameraButton extends StatefulWidget {
  const PulseCameraButton({
    super.key,
    required this.enabled,
    required this.onOpen,
  });
  final bool enabled;
  final ValueChanged<bool> onOpen;
  @override
  State<PulseCameraButton> createState() => _PulseCameraButtonState();
}

class _PulseCameraButtonState extends State<PulseCameraButton> {
  bool opened = false, held = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    // Holding belongs to the recorder, not the tooltip gesture recognizer.
    triggerMode: TooltipTriggerMode.manual,
    message: held
        ? 'Swipe up to record a video note'
        : 'Camera · hold and swipe up for video note',
    child: GestureDetector(
      onLongPressStart: widget.enabled
          ? (_) => setState(() {
              opened = false;
              held = true;
            })
          : null,
      onLongPressMoveUpdate: widget.enabled
          ? (details) {
              if (!opened && details.offsetFromOrigin.dy < -48) {
                opened = true;
                setState(() => held = false);
                widget.onOpen(true);
              }
            }
          : null,
      onLongPressEnd: (_) => setState(() => held = false),
      child: IconButton(
        onPressed: widget.enabled ? () => widget.onOpen(false) : null,
        icon: Icon(held ? Icons.arrow_upward : Icons.photo_camera_outlined),
      ),
    ),
  );
}

class PulseCameraPage extends StatefulWidget {
  const PulseCameraPage({super.key, this.note = false, this.videoOnly = false});
  final bool note, videoOnly;
  @override
  State<PulseCameraPage> createState() => _PulseCameraPageState();
}

class _PulseCameraPageState extends State<PulseCameraPage>
    with WidgetsBindingObserver {
  CameraController? camera;
  List<CameraDescription> cameras = [];
  int index = 0, elapsed = 0, generation = 0;
  bool busy = false,
      recording = false,
      video = false,
      torch = false,
      accepted = false;
  String? error;
  PulseCapture? captured;
  Player? player;
  VideoController? playback;
  Timer? timer;
  DateTime? started;
  @override
  void initState() {
    super.initState();
    video = widget.note || widget.videoOnly;
    WidgetsBinding.instance.addObserver(this);
    initialize(first: true);
  }

  Future<void> initialize({bool first = false}) async {
    if (busy) return;
    final ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    CameraController? next;
    try {
      if (first || cameras.isEmpty) {
        cameras = await availableCameras();
        if (widget.note) {
          final front = cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
          );
          if (front >= 0) index = front;
        }
      }
      if (cameras.isEmpty) throw StateError('No camera was found.');
      await camera?.dispose();
      camera = null;
      next = CameraController(
        cameras[index % cameras.length],
        ResolutionPreset.medium,
        enableAudio: video,
      );
      await next.initialize();
      if (!mounted || ticket != generation) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        busy = false;
      });
      if (widget.note && first) await record();
    } on CameraException catch (e) {
      await next?.dispose();
      if (mounted && ticket == generation)
        setState(() {
          error = e.code.toLowerCase().contains('denied')
              ? 'Allow camera and microphone access in device settings, then Retry.'
              : 'The camera could not start. Close other camera apps, then Retry.';
        });
    } catch (_) {
      await next?.dispose();
      if (mounted && ticket == generation)
        setState(
          () => error =
              'No usable camera. Check device permissions and try again.',
        );
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<void> record() async {
    if (busy || camera == null || recording) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await PulseMedia.pauseAll();
      await camera!.startVideoRecording();
      if (!mounted) return;
      started = DateTime.now();
      setState(() {
        recording = true;
        elapsed = 0;
      });
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(
          () => elapsed = DateTime.now().difference(started!).inMilliseconds,
        );
        if (elapsed >= 30000) {
          timer?.cancel();
          stop();
        }
      });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Recording could not start. Check camera and microphone permissions.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    if (busy || !recording || camera == null) return;
    setState(() => busy = true);
    timer?.cancel();
    try {
      final file = await camera!.stopVideoRecording();
      final duration = DateTime.now().difference(started!).inMilliseconds;
      recording = false;
      await preview(
        PulseCapture(
          File(file.path),
          video: true,
          round: widget.note,
          duration: duration,
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => error = 'Recording could not be saved. Please retry.');
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          recording = false;
        });
    }
  }

  Future<void> photo() async {
    if (busy || camera == null) return;
    setState(() => busy = true);
    try {
      final file = await camera!.takePicture();
      await preview(PulseCapture(File(file.path), video: false));
    } catch (_) {
      if (mounted)
        setState(() => error = 'Photo could not be captured. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> preview(PulseCapture result) async {
    captured = result;
    await camera?.dispose();
    camera = null;
    if (!mounted) {
      try {
        await result.file.delete();
      } catch (_) {}
      return;
    }
    if (result.video) {
      MediaKit.ensureInitialized();
      final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 6 * 1024 * 1024),
      );
      player = p;
      playback = VideoController(p);
      await p.open(Media(result.file.path), play: false);
    }
    if (mounted) setState(() {});
  }

  Future<void> retake() async {
    if (busy) return;
    await player?.dispose();
    player = null;
    playback = null;
    final file = captured?.file;
    captured = null;
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {}
    }
    if (mounted) await initialize();
  }

  Future<void> finish() async {
    if (busy || captured == null) return;
    await player?.pause();
    accepted = true;
    if (mounted) Navigator.pop(context, captured);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (camera == null && captured == null && !busy) initialize();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      player?.pause();
      if (recording) {
        stop();
      } else if (!busy) {
        final old = camera;
        camera = null;
        old?.dispose();
      }
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    player?.dispose();
    if (!accepted && captured != null)
      captured!.file.delete().catchError((_) => captured!.file);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view = captured != null
        ? captured!.video
              ? playback == null
                    ? const CircularProgressIndicator()
                    : Video(controller: playback!, fit: BoxFit.cover)
              : Image.file(
                  captured!.file,
                  fit: BoxFit.contain,
                  cacheWidth: 1200,
                )
        : camera?.value.isInitialized == true
        ? CameraPreview(camera!)
        : const Center(child: CircularProgressIndicator());
    if (widget.note)
      view = Center(
        child: AspectRatio(aspectRatio: 1, child: ClipOval(child: view)),
      );
    return PopScope(
      canPop: !busy && !recording,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.note ? 'Video note' : 'Camera'),
          leading: IconButton(
            tooltip: 'Cancel',
            onPressed: busy
                ? null
                : () async {
                    if (recording) await stop();
                    if (mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (!Platform.isWindows && captured == null && !recording)
              IconButton(
                tooltip: 'Light',
                onPressed: busy || camera == null
                    ? null
                    : () async {
                        try {
                          await camera!.setFlashMode(
                            torch ? FlashMode.off : FlashMode.torch,
                          );
                          if (mounted) setState(() => torch = !torch);
                        } catch (_) {
                          if (mounted)
                            setState(
                              () => error =
                                  'Light is unavailable on this camera.',
                            );
                        }
                      },
                icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
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
              if (error != null && camera == null && captured == null)
                TextButton(
                  onPressed: busy ? null : () => initialize(first: true),
                  child: const Text('Retry'),
                ),
              if (recording)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '● ${elapsed ~/ 1000}s / 30s',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              Expanded(child: view),
              if (recording)
                LinearProgressIndicator(
                  value: (elapsed / 30000).clamp(0, 1).toDouble(),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 24,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (captured != null) ...[
                      IconButton(
                        tooltip: 'Discard and retake',
                        onPressed: busy ? null : retake,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: busy ? null : finish,
                        icon: const Icon(Icons.check),
                        label: const Text('Use capture'),
                      ),
                    ] else ...[
                      if (!widget.note && !widget.videoOnly && !recording)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  video = !video;
                                  await initialize();
                                },
                          child: Text(video ? 'Video' : 'Photo'),
                        ),
                      IconButton.filled(
                        tooltip: recording
                            ? 'Stop recording'
                            : video
                            ? 'Record'
                            : 'Take photo',
                        iconSize: 48,
                        onPressed: busy || camera == null
                            ? null
                            : recording
                            ? stop
                            : video
                            ? record
                            : photo,
                        icon: Icon(
                          recording
                              ? Icons.stop_circle
                              : video
                              ? Icons.fiber_manual_record
                              : Icons.camera_alt,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Switch camera before recording',
                        onPressed: busy || recording || cameras.length < 2
                            ? null
                            : () async {
                                index = (index + 1) % cameras.length;
                                torch = false;
                                await initialize();
                              },
                        icon: const Icon(
                          Icons.cameraswitch_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
