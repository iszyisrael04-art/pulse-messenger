import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'media.dart';
import 'repository.dart' hide Row;
import 'social_repository.dart';
import 'social_preview.dart';
import 'social_upload.dart';
import 'voice.dart';

class ChannelComposer extends StatefulWidget {
  const ChannelComposer({
    super.key,
    required this.repo,
    required this.channel,
    required this.kind,
  });
  final PulseRepository repo;
  final String channel, kind;
  @override
  State<ChannelComposer> createState() => _ChannelComposerState();
}

class _ChannelComposerState extends State<ChannelComposer> {
  final caption = TextEditingController();
  final id = const Uuid().v4();
  final uploaded = <String>[];
  PulseStudioResult? selection;
  File? file;
  bool ownsFile = false,
      busy = false,
      published = false,
      uploadingComplete = false;
  String? error, path, coverPath;
  double progress = 0;
  int? duration;
  List<double> waveform = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) choose();
    });
  }

  @override
  void dispose() {
    caption.dispose();
    if (!published && uploaded.isNotEmpty)
      unawaited(
        widget.repo.db.storage
            .from('pulse-channel-media')
            .remove(uploaded)
            .then<void>((_) {})
            .catchError((_) {}),
      );
    if (ownsFile && file != null)
      unawaited(file!.delete().then<void>((_) {}).catchError((_) {}));
    super.dispose();
  }

  Future<void> choose() async {
    if (busy) return;
    setState(() => busy = true);
    File? chosen;
    bool own = false;
    try {
      await PulseMedia.pauseAll();
      if (!mounted) return;
      PulseVoiceNote? note;
      if (widget.kind == 'audio') {
        note = await showDialog<PulseVoiceNote>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const VoiceRecorderDialog(),
        );
        if (note == null) return;
        chosen = note.file;
        own = true;
      } else {
        final picked = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: widget.kind == 'video'
              ? ['mp4', 'mov', 'webm']
              : ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (picked?.path == null) return;
        chosen = File(picked!.path!);
      }
      if (!mounted) return;
      final access = await SocialStore(
        widget.repo,
      ).uploadAccess(await chosen!.length());
      if (access['allowed'] != true) {
        throw SocialFailure(
          'This file exceeds the current 2 GB hosting maximum.',
        );
      }
      PulseStudioResult? preview;
      if (widget.kind != 'audio') {
        if (!mounted) return;
        final selectedInput = chosen!;
        preview = await Navigator.push<PulseStudioResult>(
          context,
          MaterialPageRoute(
            builder: (_) => SocialSelectionPreview(
              file: selectedInput,
              video: widget.kind == 'video',
            ),
          ),
        );
        if (preview == null) return;
        own = preview.file.path != chosen!.path;
        chosen = preview.file;
      }
      if (!mounted) return;
      file = chosen;
      ownsFile = own;
      chosen = null;
      selection = preview;
      duration = note?.durationMs;
      final samples = note?.waveform ?? <double>[];
      waveform = samples.length <= 80
          ? samples
          : [
              for (var i = 0; i < 80; i++)
                samples[(i * samples.length / 80).floor()],
            ];
    } catch (e) {
      if (mounted) error = socialError(e);
    } finally {
      if (own && chosen != null) {
        try {
          await chosen.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    if (busy || file == null) return;
    setState(() {
      busy = true;
      error = null;
      progress = 0;
    });
    try {
      final access = await SocialStore(
        widget.repo,
      ).uploadAccess(await file!.length());
      if (access['allowed'] != true)
        throw SocialFailure(
          'This file exceeds the current 2 GB hosting maximum.',
        );
      final mime = mimeFor(file!.path);
      if (!uploadingComplete) {
        path =
            '${widget.channel}/${widget.repo.uid}/$id/${const Uuid().v4()}.${file!.path.split('.').last}';
        uploaded.add(path!);
        final base = Uri.parse(const String.fromEnvironment('SUPABASE_URL'));
        final endpoint = base.replace(
          host:
              base.host.endsWith('.supabase.co') &&
                  !base.host.endsWith('.storage.supabase.co')
              ? '${base.host.split('.').first}.storage.supabase.co'
              : base.host,
          path: '/storage/v1/upload/resumable',
          query: null,
          fragment: null,
        );
        await PulseTusUploader(
          endpoint: endpoint,
          bucket: 'pulse-channel-media',
          token: () async {
            final session = widget.repo.db.auth.currentSession;
            if (session == null) throw SocialFailure('Sign in again to upload');
            if (session.isExpired) await widget.repo.db.auth.refreshSession();
            return widget.repo.db.auth.currentSession!.accessToken;
          },
        ).upload(
          file!,
          path!,
          mime,
          progress: (v) {
            if (mounted) setState(() => progress = v * .95);
          },
        );
        uploadingComplete = true;
      }
      if (selection?.cover != null && coverPath == null) {
        final next =
            '${widget.channel}/${widget.repo.uid}/$id/cover-${const Uuid().v4()}.jpg';
        uploaded.add(next);
        final dir = await getTemporaryDirectory();
        final temp = File('${dir.path}/pulse-channel-cover-$id.jpg');
        try {
          await temp.writeAsBytes(selection!.cover!);
          await widget.repo.db.storage
              .from('pulse-channel-media')
              .upload(
                next,
                temp,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          coverPath = next;
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      }
      await widget.repo.rpc('channel_publish', {
        'p_id': id,
        'p_channel': widget.channel,
        'p_body': caption.text.trim(),
        'p_path': path,
        'p_kind': widget.kind,
        'p_mime': mime,
        'p_cover': coverPath,
        'p_duration': duration,
        'p_waveform': waveform,
      });
      published = true;
      // Failed earlier upload attempts are never linked to the published post.
      final orphaned = uploaded
          .where((p) => p != path && p != coverPath)
          .toList();
      if (orphaned.isNotEmpty) {
        try {
          await widget.repo.db.storage
              .from('pulse-channel-media')
              .remove(orphaned);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => progress = 1);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.kind == 'audio' ? 'Voice announcement' : 'Media announcement',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (file != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: selection?.cover != null
                        ? Image.memory(
                            selection!.cover!,
                            height: 260,
                            fit: BoxFit.contain,
                            cacheWidth: 600,
                          )
                        : widget.kind == 'image'
                        ? Image.file(
                            file!,
                            height: 260,
                            fit: BoxFit.contain,
                            cacheWidth: 600,
                          )
                        : const Padding(
                            padding: EdgeInsets.all(36),
                            child: Icon(Icons.graphic_eq, size: 64),
                          ),
                  ),
                if (file == null && !busy)
                  OutlinedButton.icon(
                    onPressed: choose,
                    icon: const Icon(Icons.add),
                    label: const Text('Choose media'),
                  ),
                const SizedBox(height: 20),
                TextField(
                  controller: caption,
                  enabled: !busy,
                  maxLength: 8000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Caption (optional)',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!),
                  ),
                if (busy && file != null) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).round()}%'),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy || file == null ? null : publish,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(busy ? 'Please wait…' : 'Publish announcement'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
