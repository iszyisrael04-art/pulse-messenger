import 'dart:io';
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
      builder: (_) => ProfileVideoEditor(file: File(picked.first.path!)),
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
  });
  final SocialStore store;
  final String path;
  @override
  State<PulseProfileBanner> createState() => _PulseProfileBannerState();
}

class _PulseProfileBannerState extends State<PulseProfileBanner> {
  Player? player;
  VideoController? controller;
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    try {
      final url = await widget.store.signed(widget.path);
      if (!mounted) return;
      final p = Player();
      player = p;
      controller = VideoController(p);
      await p.setVolume(0);
      await p.setPlaylistMode(PlaylistMode.single);
      await p.open(Media(url));
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(PulseProfileBanner old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      player?.dispose();
      player = null;
      controller = null;
      open();
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AspectRatio(
      aspectRatio: 16 / 6,
      child: controller == null
          ? const ColoredBox(
              color: Color(0xff172139),
              child: Center(child: Icon(Icons.panorama_outlined)),
            )
          : Video(
              controller: controller!,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
    ),
  );
}
