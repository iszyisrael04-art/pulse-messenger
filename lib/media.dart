import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import 'repository.dart' hide Row;

class PulseMedia {
  static Player? active;
  static Future<void> pauseAll() async {
    await active?.pause();
  }

  static Future<void> activate(Player player) async {
    if (active != player) await active?.pause();
    active = player;
  }
}

String mimeFor(String name) {
  final extension = name.split('.').last.toLowerCase();
  return {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'webm': 'video/webm',
        'm4a': 'audio/mp4',
        'mp3': 'audio/mpeg',
        'ogg': 'audio/ogg',
        'wav': 'audio/wav',
        'aac': 'audio/aac',
        'pdf': 'application/pdf',
      }[extension] ??
      'application/octet-stream';
}

String kindFor(String mime) => mime.startsWith('image/')
    ? 'image'
    : mime.startsWith('video/')
    ? 'video'
    : mime.startsWith('audio/')
    ? 'audio'
    : 'file';

class WaveformPainter extends CustomPainter {
  WaveformPainter(this.samples, this.color, {this.progress = 0});
  final List<double> samples;
  final Color color;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (samples.isEmpty) {
      paint.color = color.withValues(alpha: 0.4);
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    final count = samples.length > 80 ? 80 : samples.length;
    for (var i = 0; i < count; i++) {
      final index = (i * samples.length / count).floor();
      final height = (samples[index].clamp(0.05, 1.0)) * size.height;
      final x = (i + 0.5) * size.width / count;
      paint.color = i / count <= progress
          ? color
          : color.withValues(alpha: 0.35);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.samples != samples || old.color != color || old.progress != progress;
}

class PulseAttachment extends StatefulWidget {
  const PulseAttachment({super.key, required this.repo, required this.message});
  final PulseRepository repo;
  final Map<String, dynamic> message;
  @override
  State<PulseAttachment> createState() => _PulseAttachmentState();
}

class _PulseAttachmentState extends State<PulseAttachment>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  String? url, error;
  bool loading = false, playing = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String get kind =>
      widget.message['media_kind'] ??
      kindFor(mimeFor(widget.message['attachment_path']));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> open() async {
    if (loading) return;
    if (player != null) {
      await PulseMedia.activate(player!);
      await player!.playOrPause();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // Recheck that the message still exists and has not been deleted.
      if (widget.message['pending'] != true) {
        final current = await widget.repo.db
            .from('pulse_messages')
            .select('attachment_path,deleted_at')
            .eq('id', widget.message['id'])
            .single();
        if (current['deleted_at'] != null ||
            current['attachment_path'] != widget.message['attachment_path'])
          throw Exception('Media unavailable');
      }
      final signed = await widget.repo.db.storage
          .from('pulse-media')
          .createSignedUrl(widget.message['attachment_path'], 300);
      if (!mounted) return;
      if (kind == 'file') {
        if (!await launchUrl(
          Uri.parse(signed),
          mode: LaunchMode.externalApplication,
        ))
          throw Exception('Cannot open file');
      } else if (kind == 'image') {
        url = signed;
      } else {
        MediaKit.ensureInitialized();
        final mediaPlayer = Player();
        player = mediaPlayer;
        if (kind == 'video') video = VideoController(mediaPlayer);
        subscriptions.add(
          mediaPlayer.stream.playing.listen((value) {
            if (mounted) setState(() => playing = value);
          }),
        );
        subscriptions.add(
          mediaPlayer.stream.position.listen((value) {
            if (mounted) setState(() => position = value);
          }),
        );
        subscriptions.add(
          mediaPlayer.stream.duration.listen((value) {
            if (mounted) setState(() => duration = value);
          }),
        );
        subscriptions.add(
          mediaPlayer.stream.error.listen((_) {
            if (mounted)
              setState(
                () => error = 'Unable to play this media. Check the file format or connection.',
              );
          }),
        );
        await PulseMedia.activate(mediaPlayer);
        await mediaPlayer.open(Media(signed));
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Media is unavailable or you are offline.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    if (PulseMedia.active == player) PulseMedia.active = null;
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveform = (widget.message['waveform'] as List? ?? [])
        .whereType<num>()
        .map((x) => x.toDouble())
        .toList();
    final ms = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : (widget.message['duration_ms'] as int? ?? 0);
    final progress = ms == 0
        ? 0.0
        : (position.inMilliseconds / ms).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (kind == 'image' && url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url!,
                height: 180,
                width: 260,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Text('Photo could not load.'),
              ),
            )
          else if (kind == 'video' && video != null)
            SizedBox(height: 180, child: Video(controller: video!))
          else if (kind == 'audio')
            Row(
              children: [
                IconButton(
                  tooltip: playing ? 'Pause voice note' : 'Play voice note',
                  onPressed: loading ? null : open,
                  icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 32,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: WaveformPainter(
                            waveform,
                            Theme.of(context).colorScheme.primary,
                            progress: progress,
                          ),
                        ),
                      ),
                      Text(
                        '${position.inSeconds ~/ 60}:${(position.inSeconds % 60).toString().padLeft(2, '0')} / ${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            TextButton.icon(
              onPressed: loading ? null : open,
              icon: Icon(
                kind == 'image'
                    ? Icons.image_outlined
                    : kind == 'video'
                    ? Icons.play_circle_outline
                    : Icons.attach_file,
              ),
              label: Text(
                kind == 'image'
                    ? 'View photo'
                    : kind == 'video'
                    ? 'Play video'
                    : 'Open file',
              ),
            ),
          if (kind == 'audio' && player != null)
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: progress,
                    onChanged: (value) => player!.seek(
                      Duration(milliseconds: (value * ms).round()),
                    ),
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Playback speed',
                  onSelected: (rate) => player!.setRate(rate),
                  itemBuilder: (_) => [
                    for (final rate in [1.0, 1.5, 2.0])
                      PopupMenuItem(value: rate, child: Text('${rate}x')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.speed),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
