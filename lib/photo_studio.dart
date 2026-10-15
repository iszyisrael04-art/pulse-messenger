import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'studio_model.dart';

class PulsePhotoStudio extends StatefulWidget {
  const PulsePhotoStudio({super.key, required this.file});
  final File file;
  @override
  State<PulsePhotoStudio> createState() => _PulsePhotoStudioState();
}

class _PulsePhotoStudioState extends State<PulsePhotoStudio> {
  ui.Image? image;
  String? error;
  String tool = 'crop', filter = 'original';
  int rotation = 0;
  double? ratio;
  double brightness = 0, contrast = 1;
  bool busy = false;
  String text = '';
  final history =
      <
        ({
          int rotation,
          double? ratio,
          double brightness,
          double contrast,
          String filter,
          String text,
        })
      >[];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      if (await widget.file.length() > 100 * 1024 * 1024)
        throw StateError(
          'This photo is too large to edit safely on this device.',
        );
      buffer = await ui.ImmutableBuffer.fromFilePath(widget.file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        2048 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final value = (await codec.getNextFrame()).image;
      if (mounted)
        setState(() => image = value);
      else
        value.dispose();
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'This photo cannot be edited. Choose a JPG, PNG or WebP under 100 MB.',
        );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  void remember() => history.add((
    rotation: rotation,
    ratio: ratio,
    brightness: brightness,
    contrast: contrast,
    filter: filter,
    text: text,
  ));
  void undo() {
    if (history.isEmpty) return;
    final h = history.removeLast();
    setState(() {
      rotation = h.rotation;
      ratio = h.ratio;
      brightness = h.brightness;
      contrast = h.contrast;
      filter = h.filter;
      text = h.text;
    });
  }

  void change(VoidCallback fn) {
    remember();
    setState(fn);
  }

  Future<void> addText() async {
    final controller = TextEditingController(text: text);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(
          controller: controller,
          maxLength: 120,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Write something…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // Dispose after the dialog route's exit animation has released the field.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (value != null && mounted) change(() => text = value);
  }

  Future<void> save() async {
    if (image == null || busy) return;
    setState(() => busy = true);
    try {
      final painter = _PhotoPainter(
        image!,
        rotation,
        ratio,
        brightness,
        contrast,
        filter,
        text,
      );
      final size = painter.outputSize;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final output = await picture.toImage(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      try {
        final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('No image');
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/pulse-photo-${const Uuid().v4()}.png');
        await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        if (mounted) Navigator.pop(context, PulseStudioResult(file));
      } finally {
        output.dispose();
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Photo could not be exported. Try a smaller photo.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    image?.dispose();
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
            tooltip: 'Undo',
            onPressed: busy || history.isEmpty ? null : undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Reset',
            onPressed: busy
                ? null
                : () => change(() {
                    rotation = 0;
                    ratio = null;
                    brightness = 0;
                    contrast = 1;
                    filter = 'original';
                    text = '';
                  }),
            icon: const Icon(Icons.restart_alt),
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
                    child: Center(
                      child: image == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: AspectRatio(
                                aspectRatio: _PhotoPainter(
                                  image!,
                                  rotation,
                                  ratio,
                                  brightness,
                                  contrast,
                                  filter,
                                  text,
                                ).outputSize.aspectRatio,
                                child: CustomPaint(
                                  painter: _PhotoPainter(
                                    image!,
                                    rotation,
                                    ratio,
                                    brightness,
                                    contrast,
                                    filter,
                                    text,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final entry in {
                            'crop': Icons.crop,
                            'rotate': Icons.rotate_right,
                            'filters': Icons.filter_vintage_outlined,
                            'adjust': Icons.tune,
                            'text': Icons.text_fields,
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
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
                                            } else if (entry.key == 'text') {
                                              addText();
                                            } else {
                                              setState(() => tool = entry.key);
                                            }
                                          },
                                    icon: Icon(
                                      entry.value,
                                      color: tool == entry.key
                                          ? const Color(0xff52e0c4)
                                          : Colors.white,
                                    ),
                                  ),
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
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
                  if (tool == 'crop')
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in <String, double?>{
                            'Original': null,
                            'Square': 1,
                            'Portrait': 4 / 5,
                            'Story': 9 / 16,
                            'Wide': 16 / 9,
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(entry.key),
                                selected: ratio == entry.value,
                                onSelected: busy
                                    ? null
                                    : (_) => change(() => ratio = entry.value),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (tool == 'filters')
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final value in [
                            'original',
                            'mono',
                            'warm',
                            'cool',
                            'vivid',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(value),
                                selected: filter == value,
                                onSelected: busy
                                    ? null
                                    : (_) => change(() => filter = value),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (tool == 'adjust') ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 76,
                          child: Text(
                            'Brightness',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: brightness,
                            min: -.4,
                            max: .4,
                            onChangeStart: (_) => remember(),
                            onChanged: busy
                                ? null
                                : (v) => setState(() => brightness = v),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(
                          width: 76,
                          child: Text(
                            'Contrast',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: contrast,
                            min: .5,
                            max: 1.8,
                            onChangeStart: (_) => remember(),
                            onChanged: busy
                                ? null
                                : (v) => setState(() => contrast = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy || image == null ? null : save,
                      icon: const Icon(Icons.check),
                      label: Text(
                        busy ? 'Exporting photo…' : 'Use edited photo',
                      ),
                    ),
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

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(
    this.image,
    this.rotation,
    this.ratio,
    this.brightness,
    this.contrast,
    this.filter,
    this.text,
  );
  final ui.Image image;
  final int rotation;
  final double? ratio;
  final double brightness, contrast;
  final String filter, text;
  Size get rotated => rotation.isEven
      ? Size(image.width.toDouble(), image.height.toDouble())
      : Size(image.height.toDouble(), image.width.toDouble());
  Size get outputSize {
    final r = ratio;
    if (r == null) return rotated;
    return rotated.aspectRatio > r
        ? Size(rotated.height * r, rotated.height)
        : Size(rotated.width, rotated.width / r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final out = outputSize;
    canvas.save();
    canvas.scale(size.width / out.width, size.height / out.height);
    canvas.clipRect(Offset.zero & out);
    canvas.translate(
      (out.width - rotated.width) / 2,
      (out.height - rotated.height) / 2,
    );
    canvas.translate(rotated.width / 2, rotated.height / 2);
    canvas.rotate(rotation * 3.141592653589793 / 2);
    canvas.translate(-image.width / 2, -image.height / 2);
    final c = contrast, b = 255 * brightness + 128 * (1 - c);
    var matrix = <double>[
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
    ];
    if (filter == 'mono')
      matrix = [
        .2126 * c,
        .7152 * c,
        .0722 * c,
        0,
        b,
        .2126 * c,
        .7152 * c,
        .0722 * c,
        0,
        b,
        .2126 * c,
        .7152 * c,
        .0722 * c,
        0,
        b,
        0,
        0,
        0,
        1,
        0,
      ];
    if (filter == 'warm') {
      matrix[4] += 14;
      matrix[14] -= 12;
    }
    if (filter == 'cool') {
      matrix[4] -= 10;
      matrix[14] += 16;
    }
    if (filter == 'vivid') {
      for (final i in [0, 6, 12]) matrix[i] *= 1.12;
    }
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()
        ..colorFilter = ColorFilter.matrix(matrix)
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    if (text.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: size.width * .065,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 7)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 4,
      )..layout(maxWidth: size.width * .85);
      painter.paint(
        canvas,
        Offset((size.width - painter.width) / 2, size.height * .78),
      );
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter old) =>
      old.image != image ||
      old.rotation != rotation ||
      old.ratio != ratio ||
      old.brightness != brightness ||
      old.contrast != contrast ||
      old.filter != filter ||
      old.text != text;
}
