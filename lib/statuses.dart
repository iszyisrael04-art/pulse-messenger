import 'text_prompt.dart';
import 'social_preview.dart';
import 'media.dart';
import 'package:path_provider/path_provider.dart';
import 'channels.dart';
import 'channel_updates.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'avatar.dart';
import 'repository.dart' hide Row;

class StatusUpdates extends StatefulWidget {
  const StatusUpdates({
    super.key,
    required this.repo,
    this.onChat,
    this.updates,
  });
  final Future<void> Function(String)? onChat;
  final PulseChannelUpdates? updates;
  final PulseRepository repo;
  @override
  State<StatusUpdates> createState() => _StatusUpdatesState();
}

class _StatusUpdatesState extends State<StatusUpdates> {
  bool busy = false;
  String? error;

  Future<String?> caption({required bool textOnly}) => showPulseTextPrompt(
    context,
    textOnly ? 'Text status' : 'Add a caption',
    maxLength: 1000,
    maxLines: 4,
    allowEmpty: !textOnly,
    actionLabel: 'Post',
  );

  Future<void> post(String type) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    String? uploadedPath, uploadedCover;
    PulseStudioResult? preview;
    File? original;
    bool saved = false;
    try {
      PlatformFile? selected;
      String? mime;
      if (type != 'text') {
        selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: type == 'video'
              ? ['mp4', 'mov', 'webm']
              : ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (selected?.path == null || !mounted) return;
        final file = File(selected!.path!);
        if (await file.length() > 20 * 1024 * 1024)
          throw Exception('Status files must be under 20 MB.');
        final extension = selected.name.split('.').last.toLowerCase();
        mime = {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
          'mp4': 'video/mp4',
          'mov': 'video/quicktime',
          'webm': 'video/webm',
        }[extension];
        if (mime == null) throw Exception('Choose a supported image or video.');
      }
      if (type == 'video') {
        original = File(selected!.path!);
        await PulseMedia.pauseAll();
        if (!mounted) return;
        preview = await Navigator.push<PulseStudioResult>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SocialSelectionPreview(file: original!, video: true),
          ),
        );
        if (preview == null || !mounted) return;
        if (await preview.file.length() > 20 * 1024 * 1024)
          throw Exception('Status files must be under 20 MB.');
        mime = mimeFor(preview.file.path);
      }
      if (!mounted) return;
      final body = await caption(textOnly: type == 'text');
      if (body == null) return;
      if (type == 'text') {
        await widget.repo.rpc('post_status', {'p_body': body});
      } else {
        final id = const Uuid().v4();
        final extension = (preview?.file.path ?? selected!.name)
            .split('.')
            .last
            .toLowerCase();
        uploadedPath = '${widget.repo.uid}/$id.$extension';
        await widget.repo.db.storage
            .from('pulse-status-media')
            .upload(
              uploadedPath,
              preview?.file ?? File(selected!.path!),
              fileOptions: FileOptions(contentType: mime),
            );
        if (preview?.cover != null) {
          uploadedCover = '${widget.repo.uid}/$id-cover.jpg';
          final dir = await getTemporaryDirectory();
          final temp = File('${dir.path}/pulse-status-cover-$id.jpg');
          try {
            await temp.writeAsBytes(preview!.cover!);
            await widget.repo.db.storage
                .from('pulse-status-media')
                .upload(
                  uploadedCover,
                  temp,
                  fileOptions: const FileOptions(contentType: 'image/jpeg'),
                );
          } finally {
            if (await temp.exists()) await temp.delete();
          }
        }
        await widget.repo.rpc(
          uploadedCover == null ? 'post_media_status' : 'post_status_cover',
          {
            'p_id': id,
            'p_body': body,
            'p_path': uploadedPath,
            if (uploadedCover == null)
              'p_type': type
            else
              'p_cover': uploadedCover,
          },
        );
        saved = true;
      }
      await widget.repo.refresh();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on StorageException catch (_) {
      if (mounted)
        setState(
          () => error = 'Upload failed. Check your connection and file type.',
        );
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is SocketException
              ? 'You are offline. Reconnect before posting a status.'
              : 'Could not post: $e',
        );
    } finally {
      // Unpublished files are private; remove them if the post fails or is cancelled.
      if (uploadedPath != null && !saved) {
        try {
          final existing = await widget.repo.db
              .from('pulse_statuses')
              .select('id')
              .eq('media_path', uploadedPath)
              .maybeSingle();
          if (existing == null)
            await widget.repo.db.storage.from('pulse-status-media').remove([
              uploadedPath,
              if (uploadedCover != null) uploadedCover,
            ]);
        } catch (_) {}
      }
      if (preview != null &&
          original != null &&
          preview.file.path != original.path) {
        try {
          await preview.file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Map<String, dynamic> status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this status?'),
        content: const Text('It will disappear for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.rpc('delete_status', {'p_id': status['id']});
      final path = status['media_path'];
      if (path is String) {
        try {
          await widget.repo.db.storage.from('pulse-status-media').remove([
            path,
            if (status['cover_path'] is String) status['cover_path'] as String,
          ]);
        } catch (_) {}
      }
      await widget.repo.refresh();
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not delete the status. Please retry.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Updates',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Add status',
                icon: const Icon(Icons.add_circle_outline),
                onSelected: post,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'text', child: Text('Text status')),
                  PopupMenuItem(value: 'image', child: Text('Photo status')),
                  PopupMenuItem(value: 'video', child: Text('Video status')),
                ],
              ),
          ],
        ),
      ),
      if (error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
      Expanded(
        child: RefreshIndicator(
          onRefresh: widget.repo.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  'Status',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                height: 206,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: busy ? null : () => post('image'),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PulseAvatar(
                                repo: widget.repo,
                                path: widget.repo.me?['avatar_path'],
                                name: 'My status',
                                radius: 30,
                              ),
                              const SizedBox(height: 12),
                              const Icon(Icons.add_circle, size: 30),
                              const SizedBox(height: 8),
                              const Text('Add status'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (final status in widget.repo.statuses)
                      SizedBox(
                        width: 140,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onLongPress: status['user_id'] == widget.repo.uid
                                ? () => remove(status)
                                : null,
                            onTap: () async {
                              final chat = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StatusViewer(
                                    repo: widget.repo,
                                    status: status,
                                  ),
                                ),
                              );
                              if (chat != null && mounted)
                                await widget.onChat?.call(chat);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  PulseStatusCover(
                                    repo: widget.repo,
                                    status: status,
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black26,
                                          Colors.transparent,
                                          Colors.black87,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                      child: PulseAvatar(
                                        repo: widget.repo,
                                        path: widget
                                            .repo
                                            .profiles[status['user_id']]?['avatar_path'],
                                        name: 'Status',
                                        radius: 22,
                                      ),
                                    ),
                                  ),
                                  if (status['media_type'] == 'video')
                                    const Center(
                                      child: Icon(
                                        Icons.play_circle_outline,
                                        color: Colors.white,
                                        size: 38,
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 12,
                                    left: 10,
                                    right: 10,
                                    child: Text(
                                      status['user_id'] == widget.repo.uid
                                          ? 'My status'
                                          : widget
                                                    .repo
                                                    .profiles[status['user_id']]?['display_name'] ??
                                                'Pulse user',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 16, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Channels',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Explore channels'),
                            ),
                            body: ChannelsScreen(
                              repo: widget.repo,
                              updates: widget.updates,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Explore'),
                    ),
                  ],
                ),
              ),
              for (final channel in widget.repo.channels.where(
                (c) => widget.repo.followers.any(
                  (f) =>
                      f['channel_id'] == c['id'] &&
                      f['user_id'] == widget.repo.uid,
                ),
              ))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: PulseAvatar(
                    repo: widget.repo,
                    path: channel['avatar_path'],
                    name: channel['name'],
                    radius: 27,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          channel['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (channel['verified'] == true)
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 18,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    channel['description'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: (widget.updates?.counts[channel['id']] ?? 0) > 0
                      ? Badge(
                          label: Text(
                            '${widget.updates!.counts[channel['id']]}',
                          ),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChannelDetail(
                        repo: widget.repo,
                        channelId: channel['id'],
                        updates: widget.updates,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ],
  );
}

class PulseStatusCover extends StatefulWidget {
  const PulseStatusCover({super.key, required this.repo, required this.status});
  final PulseRepository repo;
  final Map<String, dynamic> status;
  @override
  State<PulseStatusCover> createState() => _PulseStatusCoverState();
}

class _PulseStatusCoverState extends State<PulseStatusCover> {
  late Future<String?> url;
  Future<String?> load() async {
    final path =
        widget.status['cover_path'] ??
        (widget.status['media_type'] == 'image'
            ? widget.status['media_path']
            : null);
    if (path == null) return null;
    try {
      return await widget.repo.db.storage
          .from('pulse-status-media')
          .createSignedUrl(path as String, 60);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    url = load();
  }

  @override
  void didUpdateWidget(PulseStatusCover old) {
    super.didUpdateWidget(old);
    if (old.status['id'] != widget.status['id']) url = load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: url,
    builder: (_, snap) => snap.data != null
        ? Image.network(
            snap.data!,
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (_, __, ___) => fallback(),
          )
        : fallback(),
  );
  Widget fallback() => Container(
    color: const Color(0xff244d57),
    alignment: Alignment.center,
    padding: const EdgeInsets.fromLTRB(12, 65, 12, 35),
    child: Text(
      widget.status['body'] ?? '',
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 17),
    ),
  );
}

class StatusViewer extends StatefulWidget {
  const StatusViewer({super.key, required this.repo, required this.status});
  final PulseRepository repo;
  final Map<String, dynamic> status;
  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer>
    with WidgetsBindingObserver {
  Player? player;
  VideoController? controller;
  StreamSubscription<String>? playbackErrors;
  Timer? expiry;
  String? url, error;
  bool loading = true, sending = false;
  final reply = TextEditingController();
  String? replyId;
  String? replyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    final expires = DateTime.parse(widget.status['expires_at']).toUtc();
    final remaining = expires.difference(DateTime.now().toUtc());
    expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      player?.pause();
      if (mounted)
        setState(() {
          error = 'This status has expired.';
          url = null;
        });
    });
  }

  Future<void> load() async {
    try {
      // Recheck text and media statuses alike; cached content is not authorization.
      await widget.repo.db
          .from('pulse_statuses')
          .select('id')
          .eq('id', widget.status['id'])
          .single();
      final path = widget.status['media_path'];
      if (path is String) {
        final remaining = DateTime.parse(
          widget.status['expires_at'],
        ).toUtc().difference(DateTime.now().toUtc()).inSeconds;
        if (remaining <= 0) throw Exception('Expired');
        final signed = await widget.repo.db.storage
            .from('pulse-status-media')
            .createSignedUrl(path, remaining < 60 ? remaining : 60);
        if (!mounted || error != null) return;
        url = signed;
        if (widget.status['media_type'] == 'video') {
          MediaKit.ensureInitialized();
          player = Player();
          controller = VideoController(player!);
          playbackErrors = player!.stream.error.listen((_) {
            if (mounted)
              setState(
                () => error =
                    'This video could not play. Try an MP4 encoded with H.264.',
              );
          });
          await player!.open(Media(signed));
        }
      }
      if (mounted) setState(() => loading = false);
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Status unavailable, expired, or offline.';
        });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reply.dispose();
    expiry?.cancel();
    playbackErrors?.cancel();
    player?.dispose();
    super.dispose();
  }

  Future<void> sendReply() async {
    if (sending || error != null || loading || reply.text.trim().isEmpty)
      return;
    setState(() {
      sending = true;
      replyError = null;
    });
    replyId ??= const Uuid().v4();
    try {
      final chat = await widget.repo.rpc('reply_status', {
        'p_id': replyId,
        'p_status': widget.status['id'],
        'p_body': reply.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, chat as String);
    } catch (e) {
      if (mounted)
        setState(
          () => replyError = e is PostgrestException
              ? e.message
              : 'Could not send. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff102026),
    appBar: AppBar(title: const Text('Status')),
    body: Column(
      children: [
        Expanded(
          child: Center(
            child: error != null
                ? Text(error!, style: const TextStyle(color: Colors.white))
                : loading
                ? const CircularProgressIndicator()
                : controller != null
                ? Video(controller: controller!)
                : url != null
                ? InteractiveViewer(
                    child: Image.network(
                      url!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        'Photo could not load.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.status['body'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 32, color: Colors.white),
                    ),
                  ),
          ),
        ),
        if (replyError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              replyError!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        if (widget.status['user_id'] != widget.repo.uid && error == null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: reply,
                enabled: !sending && !loading,
                maxLength: 4000,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => sendReply(),
                decoration: InputDecoration(
                  hintText: 'Reply privately…',
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(
                    Icons.donut_large,
                    color: Colors.white70,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Send status reply',
                    onPressed: sending || loading ? null : sendReply,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        if (widget.status['media_path'] != null &&
            (widget.status['body'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.status['body'],
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    ),
  );
}
