import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
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
  int timerDelay = 0, countdown = 0, recordingLimit = 15;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    video = widget.note || widget.videoOnly;
    if (widget.note) recordingLimit = 30;
    WidgetsBinding.instance.addObserver(this);
    initialize(first: true);
  }

  Future<void> initialize({bool first = false}) async {
    if (!mounted || busy || !foreground) return;
    final ticket = ++generation;
    final previous = camera;
    setState(() {
      camera = null;
      busy = true;
      error = null;
    });
    CameraController? next;
    try {
      // Remove CameraPreview from the tree before disposing its controller.
      await WidgetsBinding.instance.endOfFrame;
      await previous?.dispose();
      if (!mounted || ticket != generation || !foreground) return;
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
      next = CameraController(
        cameras[index % cameras.length],
        ResolutionPreset.medium,
        enableAudio: video,
      );
      await next.initialize();
      if (!mounted || ticket != generation || !foreground) {
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
      final active = camera;
      if (active == null || !foreground) return;
      await active.startVideoRecording();
      if (!mounted || camera != active || !foreground) {
        try {
          await active.stopVideoRecording();
        } catch (_) {}
        return;
      }
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
        if (elapsed >= recordingLimit * 1000) {
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
    if (!mounted) {
      await result.file.delete().catchError((_) => result.file);
      return;
    }
    final previous = camera;
    setState(() {
      camera = null;
      captured = result;
      recording = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    await previous?.dispose();
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
    final previous = player;
    final file = captured?.file;
    setState(() {
      player = null;
      playback = null;
      captured = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await previous?.dispose();
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

  Future<void> upload() async {
    if (busy || recording || widget.note) return;
    setState(() => busy = true);
    File? copy;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: widget.videoOnly
            ? ['mp4', 'mov', 'webm']
            : ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm'],
      );
      if (picked?.path == null || !mounted) return;
      final ext = picked!.name.split('.').last.toLowerCase();
      final directory = await getTemporaryDirectory();
      copy = await File(picked.path!).copy(
        '${directory.path}/pulse-capture-${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      await preview(
        PulseCapture(copy, video: ['mp4', 'mov', 'webm'].contains(ext)),
      );
      copy = null;
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'This media could not be opened. Please try another file.',
        );
    } finally {
      if (copy != null) await copy.delete().catchError((_) => copy!);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> shutter() async {
    if (busy || camera == null) return;
    if (recording) return stop();
    final ticket = generation;
    if (timerDelay > 0) {
      setState(() {
        busy = true;
        countdown = timerDelay;
      });
      for (var left = timerDelay; left > 0; left--) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || ticket != generation || !foreground) return;
        setState(() => countdown = left - 1);
      }
      setState(() => busy = false);
    }
    if (!mounted || !foreground || camera == null) return;
    if (video) {
      await record();
    } else {
      await photo();
    }
  }

  Future<void> light() async {
    final active = camera;
    if (busy || active == null) return;
    try {
      await active.setFlashMode(torch ? FlashMode.off : FlashMode.torch);
      if (mounted && camera == active) setState(() => torch = !torch);
    } catch (_) {
      if (mounted)
        setState(() => error = 'Light is unavailable on this camera.');
    }
  }

  Future<void> flip() async {
    if (busy || recording || cameras.length < 2) return;
    index = (index + 1) % cameras.length;
    torch = false;
    await initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      foreground = true;
      if (camera == null && captured == null && !busy) initialize();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      foreground = false;
      player?.pause();
      if (recording && !busy) {
        stop();
      } else if (!busy || countdown > 0) {
        generation++;
        final previous = camera;
        setState(() {
          camera = null;
          countdown = 0;
          busy = false;
        });
        WidgetsBinding.instance.endOfFrame.then((_) => previous?.dispose());
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

  Widget cameraTool(IconData icon, String label, VoidCallback? action) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            IconButton.filledTonal(
              onPressed: action,
              tooltip: label,
              icon: Icon(icon),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      );

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
                    '● ${elapsed ~/ 1000}s / ${recordingLimit}s',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    view,
                    if (countdown > 0)
                      Center(
                        child: Text(
                          '$countdown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 84,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (captured == null && !recording)
                      Positioned(
                        right: 12,
                        top: 16,
                        child: Column(
                          children: [
                            cameraTool(
                              Icons.cameraswitch_outlined,
                              'Flip',
                              busy || cameras.length < 2 ? null : flip,
                            ),
                            if (!Platform.isWindows)
                              cameraTool(
                                torch ? Icons.flash_on : Icons.flash_off,
                                torch ? 'On' : 'Off',
                                busy || camera == null ? null : light,
                              ),
                            if (!widget.note)
                              cameraTool(
                                Icons.timer_outlined,
                                timerDelay == 0 ? 'Timer' : '${timerDelay}s',
                                busy
                                    ? null
                                    : () => setState(
                                        () => timerDelay = timerDelay == 0
                                            ? 3
                                            : timerDelay == 3
                                            ? 10
                                            : 0,
                                      ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (recording)
                LinearProgressIndicator(
                  value: (elapsed / (recordingLimit * 1000))
                      .clamp(0, 1)
                      .toDouble(),
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
                      if (!widget.note && !recording)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final seconds in [15, 60, 180])
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        setState(() {
                                          video = true;
                                          recordingLimit = seconds;
                                        });
                                        await initialize();
                                      },
                                child: Text(
                                  seconds == 180 ? '3m' : '${seconds}s',
                                  style: TextStyle(
                                    color: video && recordingLimit == seconds
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            if (!widget.videoOnly)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        setState(() => video = false);
                                        await initialize();
                                      },
                                child: Text(
                                  'Photo',
                                  style: TextStyle(
                                    color: !video
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (!widget.note && !recording)
                        IconButton(
                          tooltip: 'Upload photo or video',
                          onPressed: busy ? null : upload,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                          ),
                        ),
                      IconButton.filled(
                        tooltip: recording
                            ? 'Stop recording'
                            : video
                            ? 'Record'
                            : 'Take photo',
                        iconSize: 48,
                        onPressed: busy || camera == null ? null : shutter,
                        icon: Icon(
                          recording
                              ? Icons.stop_circle
                              : video
                              ? Icons.fiber_manual_record
                              : Icons.camera_alt,
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
