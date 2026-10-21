import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'chat_camera.dart';
import 'media.dart';

class PulsePickedMedia {
  const PulsePickedMedia(this.file, {this.owned = false});
  final File file;
  final bool owned;
  String get name => file.uri.pathSegments.last;
  bool get video => kindFor(mimeFor(name)) == 'video';
}

class PulseMediaPicker extends StatefulWidget {
  const PulseMediaPicker({
    super.key,
    this.videoOnly = false,
    this.remaining = 8,
  });
  final bool videoOnly;
  final int remaining;
  @override
  State<PulseMediaPicker> createState() => _PulseMediaPickerState();
}

class _PulseMediaPickerState extends State<PulseMediaPicker> {
  final selected = <PulsePickedMedia>[];
  bool busy = false, delivered = false;
  String tab = 'all';
  String? error;
  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.videoOnly || tab == 'video'
            ? ['mp4', 'mov', 'webm']
            : tab == 'image'
            ? ['jpg', 'jpeg', 'png', 'webp']
            : ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm'],
      );
      if (!mounted) return;
      for (final file in files) {
        if (file.path != null) add(PulsePickedMedia(File(file.path!)));
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not open your media. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void add(PulsePickedMedia file) {
    if (selected.any((m) => m.file.path == file.file.path)) return;
    if (selected.isNotEmpty && (file.video || selected.first.video) ||
        selected.length >= widget.remaining) {
      error =
          'Choose up to ${widget.remaining} photos or one video. Remove the current selection to switch.';
      if (file.owned) file.file.delete().catchError((_) => file.file);
    } else {
      selected.add(file);
    }
    setState(() {});
  }

  Future<void> camera() async {
    setState(() => busy = true);
    try {
      final value = await Navigator.push<PulseCapture>(
        context,
        MaterialPageRoute(
          builder: (_) => PulseCameraPage(videoOnly: widget.videoOnly),
        ),
      );
      if (value != null) {
        if (mounted)
          add(PulsePickedMedia(value.file, owned: true));
        else {
          try {
            await value.file.delete();
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void remove(PulsePickedMedia item) {
    setState(() => selected.remove(item));
    if (item.owned) item.file.delete().catchError((_) => item.file);
  }

  @override
  void dispose() {
    if (!delivered)
      for (final item in selected.where((i) => i.owned)) {
        item.file.delete().catchError((_) => item.file);
      }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select media')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : camera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose media'),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.videoOnly)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'video', label: Text('Videos')),
                ButtonSegment(value: 'image', label: Text('Photos')),
              ],
              selected: {tab},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => tab = v.first),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: selected.isEmpty
                ? const Center(child: Text('Choose media to preview it here.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: .8,
                        ),
                    itemCount: selected.length,
                    itemBuilder: (_, i) => Stack(
                      fit: StackFit.expand,
                      children: [
                        PulseLocalMediaCover(
                          key: ValueKey(selected[i].file.path),
                          file: selected[i].file,
                          video: selected[i].video,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filled(
                            tooltip: 'Remove',
                            onPressed: busy ? null : () => remove(selected[i]),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: CircleAvatar(
                            radius: 13,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy || selected.isEmpty
                    ? null
                    : () {
                        delivered = true;
                        Navigator.pop(
                          context,
                          List<PulsePickedMedia>.of(selected),
                        );
                      },
                child: Text('Edit selected (${selected.length})'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PulseLocalMediaCover extends StatefulWidget {
  const PulseLocalMediaCover({
    super.key,
    required this.file,
    required this.video,
  });
  final File file;
  final bool video;
  @override
  State<PulseLocalMediaCover> createState() => _PulseLocalMediaCoverState();
}

class _PulseLocalMediaCoverState extends State<PulseLocalMediaCover> {
  Player? player;
  VideoController? controller;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    if (widget.video) open();
  }

  Future<void> open() async {
    try {
      MediaKit.ensureInitialized();
      final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 2 * 1024 * 1024),
      );
      player = p;
      controller = VideoController(p);
      await p.open(Media(widget.file.path), play: false);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.video
      ? Image.file(
          widget.file,
          fit: BoxFit.cover,
          cacheWidth: 360,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        )
      : failed
      ? const Icon(Icons.videocam_off_outlined)
      : controller == null
      ? const Center(child: CircularProgressIndicator())
      : IgnorePointer(
          child: Video(controller: controller!, fit: BoxFit.cover),
        );
}
