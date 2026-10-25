import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'profile_video.dart';
import 'social_repository.dart';

Future<void> editFreeProfileBanner(
  BuildContext context,
  SocialStore store,
  bool private,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['mp4', 'mov'],
  );
  if (picked.isEmpty || picked.first.path == null || !context.mounted) return;
  final result = await Navigator.push<ProfileVideoResult>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ProfileVideoEditor(file: File(picked.first.path!), banner: true),
    ),
  );
  if (result == null) return;
  try {
    if (await result.video.length() > 10485760)
      throw StateError('Banner must be under 10 MB.');
    final path = '${store.uid}/cover/${const Uuid().v4()}.mp4';
    await store.repo.db.storage
        .from('pulse-social')
        .upload(
          path,
          result.video,
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );
    await store.rpc('account', {'p_private': private, 'p_cover': path});
  } finally {
    if (await result.video.exists()) await result.video.delete();
    if (await result.poster.exists()) await result.poster.delete();
  }
}

class PulseProfileBanner extends StatefulWidget {
  const PulseProfileBanner({
    super.key,
    required this.store,
    required this.path,
    this.fill = false,
  });
  final SocialStore store;
  final String path;
  final bool fill;
  @override
  State<PulseProfileBanner> createState() => _PulseProfileBannerState();
}

class _PulseProfileBannerState extends State<PulseProfileBanner>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  int generation = 0;
  bool motionAllowed = true, foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motionAllowed =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    unawaited(syncPlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    unawaited(syncPlayback());
  }

  Future<void> syncPlayback() async {
    final p = player;
    if (p == null) return;
    try {
      if (motionAllowed && foreground) {
        await p.play();
      } else {
        await p.pause();
      }
    } catch (_) {}
  }

  Future<void> open() async {
    final ticket = ++generation;
    try {
      final url = await widget.store.signed(widget.path);
      if (!mounted || ticket != generation) return;
      final p = Player();
      player = p;
      controller = VideoController(p);
      await p.setVolume(0);
      await p.setPlaylistMode(PlaylistMode.single);
      await p.open(Media(url), play: false);
      if (!mounted || ticket != generation) return;
      await syncPlayback();
      if (mounted && ticket == generation) setState(() {});
    } catch (_) {
      if (mounted && ticket == generation) setState(() {});
    }
  }

  @override
  void didUpdateWidget(PulseProfileBanner old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.store != widget.store) {
      player?.dispose();
      player = null;
      controller = null;
      open();
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = controller == null
        ? const ColoredBox(color: Color(0xff172139))
        : Video(
            controller: controller!,
            fit: BoxFit.cover,
            controls: NoVideoControls,
          );
    if (widget.fill) return media;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(aspectRatio: 16 / 6, child: media),
    );
  }
}
