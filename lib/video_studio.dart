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
import 'text_prompt.dart';
import 'edit_history.dart';

typedef _VideoEdit = ({
  double start,
  double end,
  bool mute,
  int rotation,
  double? ratio,
  double brightness,
  double contrast,
  bool mono,
  String text,
});

class PulseVideoStudio extends StatefulWidget {
  const PulseVideoStudio({super.key, required this.file, this.caption});
  final File file;
  final String? caption;
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
  int rotation = 0;
  double? ratio;
  double brightness = 0, contrast = 0;
  bool mono = false;
  String overlayText = '';
  final history = PulseEditHistory<_VideoEdit>();
  _VideoEdit get edit => (
    start: trim.start,
    end: trim.end,
    mute: mute,
    rotation: rotation,
    ratio: ratio,
    brightness: brightness,
    contrast: contrast,
    mono: mono,
    text: overlayText,
  );

  void remember() => history.remember(edit);

  void restore(_VideoEdit value) {
    setState(() {
      trim = RangeValues(value.start, value.end);
      mute = value.mute;
      rotation = value.rotation;
      ratio = value.ratio;
      brightness = value.brightness;
      contrast = value.contrast;
      mono = value.mono;
      overlayText = value.text;
      cover = null;
    });
    player?.setVolume(mute ? 0 : 100);
    player?.seek(Duration(milliseconds: trim.start.round()));
  }

  void change(VoidCallback update) {
    remember();
    setState(update);
  }

  bool get styled =>
      rotation != 0 ||
      ratio != null ||
      brightness != 0 ||
      contrast != 0 ||
      mono ||
      overlayText.isNotEmpty;
  Map<String, dynamic> get styles => {
    'rotation': rotation,
    'ratio': ratio,
    'brightness': brightness,
    'contrast': contrast,
    'mono': mono,
    'text': overlayText,
  };
  Future<void> addOverlay() async {
    final text = await showPulseTextPrompt(
      context,
      'Video text',
      initial: overlayText,
      maxLength: 80,
      allowEmpty: true,
    );
    if (text != null && mounted && text != overlayText) {
      change(() => overlayText = text);
    }
  }

  Widget preview() {
    Widget view = Video(controller: controller!, fit: BoxFit.cover);
    if (Platform.isAndroid) {
      if (mono)
        view = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: view,
        );
      final c = 1 + contrast, b = brightness * 255 + 128 * (1 - (1 + contrast));
      view = ColorFiltered(
        colorFilter: ColorFilter.matrix([
          c,
          0,
          0,
          0,
          b,
          0,
          c,
          0,
          0,
          b,
          0,
          0,
          c,
          0,
          b,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: view,
      );
      view = RotatedBox(quarterTurns: rotation, child: view);
      if (ratio != null)
        view = Center(
          child: AspectRatio(
            aspectRatio: ratio!,
            child: ClipRect(child: view),
          ),
        );
      view = Stack(
        fit: StackFit.expand,
        children: [
          view,
          if (overlayText.isNotEmpty)
            Align(
              alignment: const Alignment(0, .65),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  overlayText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return view;
  }

  String? error;
  double progress = 0;
  Uint8List? cover;
  late final TextEditingController caption;
  @override
  void initState() {
    super.initState();
    caption = TextEditingController(text: widget.caption ?? '');
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
    File? exported, styledFile;
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
      if (styled) {
        final dir = await getTemporaryDirectory();
        styledFile = File('${dir.path}/pulse-style-${const Uuid().v4()}.mp4');
        file = await NativePulseEditor.style(file, styledFile, styles, (v) {
          if (mounted) setState(() => progress = v);
        });
        await player!.open(Media(file.path), play: false);
        await player!.seek(const Duration(milliseconds: 100));
        cover = null;
        for (var attempt = 0; attempt < 8 && cover == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          cover = await player!.screenshot(format: 'image/jpeg');
        }
        if (cover == null)
          throw StateError('The edited cover could not be generated.');
        if (exported != null && await exported.exists())
          await exported.delete();
      }
      if (mounted)
        Navigator.pop(
          context,
          PulseStudioResult(file, cover: cover, caption: caption.text),
        );
    } catch (e) {
      if (styledFile != null && await styledFile.exists())
        await styledFile.delete();
      if (exported != null && await exported.exists()) await exported.delete();
      try {
        await player?.open(Media(widget.file.path), play: false);
      } catch (_) {}
      if (mounted)
        setState(
          () => error =
              'Video export could not finish. Try fewer effects or a smaller MP4.',
        );
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
    caption.dispose();
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
          IconButton(
            tooltip: 'Undo edit',
            onPressed: busy || !history.canUndo
                ? null
                : () => restore(history.undo(edit)),
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo edit',
            onPressed: busy || !history.canRedo
                ? null
                : () => restore(history.redo(edit)),
            icon: const Icon(Icons.redo_rounded),
          ),
          TextButton(
            onPressed: busy || !ready
                ? null
                : () {
                    change(() {
                      trim = RangeValues(0, duration.inMilliseconds.toDouble());
                      mute = false;
                      cover = null;
                      rotation = 0;
                      ratio = null;
                      brightness = 0;
                      contrast = 0;
                      mono = false;
                      overlayText = "";
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
                        : preview(),
                  ),
                  SizedBox(
                    width: 76,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final entry in {
                            'trim': Icons.content_cut,
                            'mute': mute ? Icons.volume_off : Icons.volume_up,
                            'cover': Icons.image_outlined,
                            if (Platform.isAndroid) ...{
                              'crop': Icons.crop_rounded,
                              'rotate': Icons.rotate_right_rounded,
                              'adjust': Icons.tune_rounded,
                              'mono': Icons.filter_b_and_w,
                              'text': Icons.text_fields,
                            },
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
                                            if (entry.key == 'rotate') {
                                              change(
                                                () => rotation =
                                                    (rotation + 1) % 4,
                                              );
                                            } else if (entry.key == 'mono') {
                                              change(() => mono = !mono);
                                            } else if (entry.key == 'text') {
                                              addOverlay();
                                            } else if (entry.key == 'mute') {
                                              change(() => mute = !mute);
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
                  ),
                ],
              ),
            ),
            if (widget.caption != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: TextField(
                  controller: caption,
                  maxLength: 8000,
                  maxLines: 2,
                  readOnly: busy,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Add a caption…',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterText: '',
                  ),
                ),
              ),
            Container(
              color: const Color(0xff151922),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Platform.isAndroid && tool == 'crop')
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final option in <String, double?>{
                          'Original': null,
                          '9:16': 9 / 16,
                          'Square': 1,
                          '4:5': 4 / 5,
                          '16:9': 16 / 9,
                        }.entries)
                          ChoiceChip(
                            label: Text(option.key),
                            selected: ratio == option.value,
                            onSelected: busy
                                ? null
                                : (_) => change(() => ratio = option.value),
                          ),
                      ],
                    ),
                  if (Platform.isAndroid && tool == 'adjust') ...[
                    const Text(
                      'Brightness',
                      style: TextStyle(color: Colors.white),
                    ),
                    Slider(
                      onChangeStart: busy ? null : (_) => remember(),
                      value: brightness,
                      min: -.4,
                      max: .4,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => brightness = v),
                    ),
                    const Text(
                      'Contrast',
                      style: TextStyle(color: Colors.white),
                    ),
                    Slider(
                      onChangeStart: busy ? null : (_) => remember(),
                      value: contrast,
                      min: -.5,
                      max: .5,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => contrast = v),
                    ),
                  ],
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
                      onChangeStart: busy || !ready ? null : (_) => remember(),
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
                  if (ready && !busy) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.movie_outlined,
                          color: Colors.white54,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${time(position.inMilliseconds.toDouble())} / ${time(trim.end)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        Text(
                          '${((trim.end - trim.start) / 1000).toStringAsFixed(1)}s selected',
                          style: const TextStyle(
                            color: Color(0xff52e0c4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: position.inMilliseconds.toDouble().clamp(
                        trim.start,
                        trim.end,
                      ),
                      min: trim.start,
                      max: trim.end,
                      onChangeStart: (_) => player?.pause(),
                      onChanged: (value) =>
                          player?.seek(Duration(milliseconds: value.round())),
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
