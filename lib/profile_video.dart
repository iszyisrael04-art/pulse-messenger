import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'native_editor.dart';
import 'profile_media_rules.dart';

typedef ProfileVideoResult = ({File video, File poster});

/// Exports an actual muted MP4, rather than retaining the full selected video.
class ProfileVideoEditor extends StatefulWidget {
  const ProfileVideoEditor({super.key, required this.file});
  final File file;
  @override
  State<ProfileVideoEditor> createState() => _ProfileVideoEditorState();
}

class _ProfileVideoEditorState extends State<ProfileVideoEditor> {
  Player? player;
  VideoController? controller;
  StreamSubscription<Duration>? position;
  StreamSubscription<String>? errors;
  StreamSubscription<Duration>? durations;
  int durationMs = 0, startMs = 0;
  bool busy = false, ready = false, seeking = false;
  double progress = 0;
  String? error;
  int get lengthMs => durationMs.clamp(0, maxProfileVideoMs);
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    try {
      MediaKit.ensureInitialized();
      final own = Player(
        configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
      );
      player = own;
      controller = VideoController(own);
      durations = own.stream.duration.listen((value) {
        if (mounted && value.inMilliseconds > 0)
          setState(() {
            durationMs = value.inMilliseconds;
            startMs = startMs.clamp(
              0,
              (durationMs - lengthMs).clamp(0, durationMs),
            );
            ready = true;
          });
      });
      position = own.stream.position.listen((value) async {
        if (!mounted ||
            !ready ||
            busy ||
            seeking ||
            value.inMilliseconds < startMs + lengthMs)
          return;
        seeking = true;
        try {
          await own.seek(Duration(milliseconds: startMs));
        } finally {
          seeking = false;
        }
      });
      errors = own.stream.error.listen((_) {
        if (mounted)
          setState(() => error = 'Could not preview this video. Try an MP4.');
      });
      await own.setVolume(0);
      await own.setPlaylistMode(PlaylistMode.loop);
      await own.open(Media(widget.file.path));
    } catch (_) {
      if (mounted)
        setState(() => error = 'This device could not preview the video.');
    }
  }

  Future<void> export() async {
    if (!ready || busy || error != null) return;
    setState(() {
      busy = true;
      progress = 0;
    });
    Directory? work;
    try {
      await player!.pause();
      await player!.seek(Duration(milliseconds: startMs));
      final bytes = await player!.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) throw StateError('No preview frame');
      work = Directory(
        '${(await getTemporaryDirectory()).path}/pulse-avatar-${const Uuid().v4()}',
      );
      await work.create();
      final poster = File('${work.path}/poster.jpg');
      await poster.writeAsBytes(bytes, flush: true);
      final output = File('${work.path}/motion.mp4');
      final clip = profileVideoRange(durationMs, startMs);
      await NativePulseEditor.avatar(
        widget.file,
        output,
        clip.start,
        clip.end,
        (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (await output.length() > 15728640)
        throw StateError(
          'Profile video exceeds 15 MB. Try a smaller source video.',
        );
      if (!mounted) {
        await work.delete(recursive: true);
        return;
      }
      Navigator.pop<ProfileVideoResult>(context, (
        video: output,
        poster: poster,
      ));
    } catch (e) {
      if (work != null && await work.exists())
        await work.delete(recursive: true);
      if (mounted)
        setState(() {
          error = 'Could not export this clip. Try a smaller MP4 video.';
          busy = false;
        });
    }
  }

  @override
  void dispose() {
    position?.cancel();
    errors?.cancel();
    durations?.cancel();
    final old = player;
    // Detach the texture from the widget tree before destroying its player.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Trim profile video')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Choose a five-second moment. Profile videos play silently.',
          ),
          const SizedBox(height: 24),
          Center(
            child: ClipOval(
              child: SizedBox.square(
                dimension: 240,
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : Video(
                        controller: controller!,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '${(startMs / 1000).toStringAsFixed(1)}–${((startMs + lengthMs) / 1000).toStringAsFixed(1)} seconds',
          ),
          if (ready && durationMs > maxProfileVideoMs)
            Slider(
              value: startMs.toDouble(),
              min: 0,
              max: (durationMs - lengthMs).toDouble(),
              label: '${(startMs / 1000).toStringAsFixed(1)}s',
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() => startMs = value.round());
                    },
              onChangeEnd: busy
                  ? null
                  : (_) async {
                      await player?.seek(Duration(milliseconds: startMs));
                      await player?.play();
                    },
            ),
          if (ready && durationMs <= maxProfileVideoMs)
            const Text(
              'This video is shorter than five seconds; the full clip will loop.',
            ),
          if (busy) LinearProgressIndicator(value: progress),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ready && !busy && error == null ? export : null,
            child: Text(busy ? 'Preparing profile video…' : 'Use this clip'),
          ),
        ],
      ),
    ),
  );
}
