import 'package:flutter/material.dart';
import 'media.dart';
import 'repository.dart' hide Row;
import 'social_download.dart';
import 'social_repository.dart';

class ChannelPostMedia extends StatefulWidget {
  const ChannelPostMedia({super.key, required this.repo, required this.post});
  final PulseRepository repo;
  final Map<String, dynamic> post;
  @override
  State<ChannelPostMedia> createState() => _ChannelPostMediaState();
}

class _ChannelPostMediaState extends State<ChannelPostMedia> {
  late Future<String?> cover;
  bool opened = false, downloading = false;
  @override
  void initState() {
    super.initState();
    cover = loadCover();
  }

  Future<String?> loadCover() async {
    final path = widget.post['cover_path'];
    if (path is! String) return null;
    try {
      return await widget.repo.db.storage
          .from('pulse-channel-media')
          .createSignedUrl(path, 300);
    } catch (_) {
      return null;
    }
  }

  Future<void> download() async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      final fresh = await widget.repo.rpc('channel_entry', {
        'p_post': widget.post['id'],
      });
      if (fresh == null)
        throw SocialFailure('This announcement is unavailable.');
      if (!mounted) return;
      await PulseMedia.pauseAll();
      if (!mounted) return;
      await downloadPulseMedia(
        context,
        {
          'kind': fresh['media_kind'],
          'path': fresh['attachment_path'],
          'mime': fresh['media_mime'],
          'name':
              'Pulse-channel.${fresh['attachment_path'].toString().split('.').last}',
        },
        username: fresh['username'],
        signedUrl: () => widget.repo.db.storage
            .from('pulse-channel-media')
            .createSignedUrl(fresh['attachment_path'], 300),
        stillAllowed: () async =>
            await widget.repo.rpc('channel_entry', {
              'p_post': widget.post['id'],
            }) !=
            null,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(socialError(e))));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.post['media_kind'] == 'video' && !opened)
        FutureBuilder<String?>(
          future: cover,
          builder: (_, snap) => SizedBox(
            width: 280,
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (snap.data != null)
                  Image.network(
                    snap.data!,
                    fit: BoxFit.cover,
                    cacheWidth: 560,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Colors.black12),
                  )
                else
                  const ColoredBox(color: Colors.black12),
                Center(
                  child: IconButton.filled(
                    tooltip: 'Play video',
                    onPressed: () => setState(() => opened = true),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ),
              ],
            ),
          ),
        )
      else
        PulseAttachment(
          repo: widget.repo,
          message: widget.post,
          channel: true,
          autoplay: opened,
        ),
      Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<String>(
          tooltip: 'Media options',
          enabled: !downloading,
          onSelected: (_) => download(),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'download',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.download_outlined),
                title: Text('Download'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
