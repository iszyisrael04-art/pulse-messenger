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
  const StatusUpdates({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<StatusUpdates> createState() => _StatusUpdatesState();
}

class _StatusUpdatesState extends State<StatusUpdates> {
  bool busy = false;
  String? error;

  Future<String?> caption({required bool textOnly}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(textOnly ? 'Text status' : 'Add a caption'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!textOnly || value.isNotEmpty) Navigator.pop(dialog, value);
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> post(String type) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    String? uploadedPath;
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
      if (!mounted) return;
      final body = await caption(textOnly: type == 'text');
      if (body == null) return;
      if (type == 'text') {
        await widget.repo.rpc('post_status', {'p_body': body});
      } else {
        final id = const Uuid().v4();
        final extension = selected!.name.split('.').last.toLowerCase();
        uploadedPath = '${widget.repo.uid}/$id.$extension';
        await widget.repo.db.storage
            .from('pulse-status-media')
            .upload(
              uploadedPath,
              File(selected.path!),
              fileOptions: FileOptions(contentType: mime),
            );
        await widget.repo.rpc('post_media_status', {
          'p_id': id,
          'p_body': body,
          'p_path': uploadedPath,
          'p_type': type,
        });
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
          await widget.repo.db.storage.from('pulse-status-media').remove([
            uploadedPath,
          ]);
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
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Visible to people who share a chat with you. Expires after 24 hours. Photos and videos: up to 20 MB.',
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
              if (widget.repo.statuses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No active statuses. Add your first update above.',
                  ),
                ),
              for (final status in widget.repo.statuses)
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: PulseAvatar(
                      repo: widget.repo,
                      path: widget
                          .repo
                          .profiles[status['user_id']]?['avatar_path'],
                      name:
                          widget
                              .repo
                              .profiles[status['user_id']]?['display_name'] ??
                          'Pulse user',
                    ),
                    title: Text(
                      status['user_id'] == widget.repo.uid
                          ? 'My status'
                          : widget
                                    .repo
                                    .profiles[status['user_id']]?['display_name'] ??
                                'Pulse user',
                    ),
                    subtitle: Text(
                      status['media_type'] == 'video'
                          ? 'Video · tap to play'
                          : status['media_type'] == 'image'
                          ? 'Photo · tap to view'
                          : status['body'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: status['user_id'] == widget.repo.uid
                        ? IconButton(
                            tooltip: 'Delete status',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => remove(status),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            StatusViewer(repo: widget.repo, status: status),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
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
  bool loading = true;

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
      final path = widget.status['media_path'];
      if (path is String) {
        // Recheck access and expiration rather than trusting the cached status list.
        await widget.repo.db
            .from('pulse_statuses')
            .select('id')
            .eq('id', widget.status['id'])
            .single();
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
    expiry?.cancel();
    playbackErrors?.cancel();
    player?.dispose();
    super.dispose();
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
