import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'media.dart';
import 'social_repository.dart';
import 'social_media.dart';
import 'social_preview.dart';
import 'media_picker.dart';
import 'chat_camera.dart';

class SocialComposer extends StatefulWidget {
  const SocialComposer({
    super.key,
    required this.store,
    this.draft,
    this.reel = false,
  });
  final SocialStore store;
  final SocialRow? draft;
  final bool reel;
  @override
  State<SocialComposer> createState() => _SocialComposerState();
}

class _SocialComposerState extends State<SocialComposer> {
  late final String id;
  late final TextEditingController body;
  late String kind, audience;
  final media = <SocialRow>[];
  bool busy = false, dirty = false, saved = false;
  int completed = 0, total = 0;
  String? error;
  double? progress;
  @override
  void initState() {
    super.initState();
    id = widget.draft?['id'] ?? const Uuid().v4();
    body = TextEditingController(text: widget.draft?['body'] ?? '');
    kind = widget.draft?['kind'] ?? (widget.reel ? 'reel' : 'post');
    audience = widget.draft?['audience'] ?? 'public';
    media.addAll(
      (widget.draft?['media'] as List? ?? []).map(
        (x) => Map<String, dynamic>.from(x as Map),
      ),
    );
    body.addListener(() => dirty = true);
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> capture() async {
    if (busy) return;
    setState(() => busy = true);
    PulseCapture? result;
    try {
      result = await Navigator.push<PulseCapture>(
        context,
        MaterialPageRoute(
          builder: (_) => PulseCameraPage(videoOnly: kind == 'reel'),
        ),
      );
      if (result != null && mounted) {
        await chooseAndUpload(PulsePickedMedia(result.file, owned: true));
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (result != null)
        await result.file.delete().catchError((_) => result!.file);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final selections = await Navigator.push<List<PulsePickedMedia>>(
        context,
        MaterialPageRoute(
          builder: (_) => PulseMediaPicker(
            videoOnly: kind == 'reel',
            remaining: (8 - media.length).clamp(1, 8),
          ),
        ),
      );
      if (selections == null) return;
      try {
        for (final selected in selections) {
          if (!mounted) break;
          await chooseAndUpload(selected);
        }
      } finally {
        for (final selected in selections.where((p) => p.owned)) {
          try {
            if (await selected.file.exists()) await selected.file.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseAndUpload(PulsePickedMedia selected) async {
    if (media.length >= 8) {
      setState(() => error = 'Choose up to 8 photos or one video.');
      return;
    }
    final mime = mimeFor(selected.name), mediaKind = kindFor(mime);
    final file = selected.file;
    try {
      final access = await widget.store.uploadAccess(await file.length());
      if (!mounted) return;
      if (access['allowed'] != true) {
        throw SocialFailure(
          'This file exceeds the current 2 GB hosting maximum.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
      return;
    }
    if (!mounted) return;
    final preview = await Navigator.push<PulseStudioResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SocialSelectionPreview(file: file, video: mediaKind == 'video'),
      ),
    );
    if (preview == null || !mounted) return;

    if (media.isNotEmpty &&
        (mediaKind == 'video' || media.first['kind'] == 'video')) {
      setState(
        () => error =
            'Photos can be added together. Remove current media to switch to a video.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      total = media.length + 1;
      completed = media.length;
      progress = 0;
    });
    try {
      final path = await widget.store.upload(
        preview.file,
        preview.file.uri.pathSegments.last,
        id,
        progress: (v) {
          if (mounted) setState(() => progress = v);
        },
      );
      String? coverPath;
      if (preview.cover != null) {
        final dir = await getTemporaryDirectory();
        final cover = File('${dir.path}/pulse-cover-${const Uuid().v4()}.jpg');
        try {
          await cover.writeAsBytes(preview.cover!);
          coverPath = await widget.store.upload(cover, 'video-cover.jpg', id);
        } finally {
          if (await cover.exists()) await cover.delete();
        }
      }
      if (!mounted) return;
      setState(() {
        media.add({
          'path': path,
          'kind': mediaKind,
          'mime': mimeFor(preview.file.path),
          'name': preview.file.uri.pathSegments.last,
          if (coverPath != null) 'cover_path': coverPath,
        });
        completed++;
        dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      // Only remove files created by Studio; never delete the selected original.
      try {
        if (preview.file.path != file.path && await preview.file.exists()) {
          await preview.file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> submit(bool draft) async {
    if (busy) return;
    if (body.text.trim().isEmpty && media.isEmpty) {
      setState(() => error = 'Add text or media first.');
      return;
    }
    if (kind == 'reel' &&
        (media.length != 1 || media.first['kind'] != 'video')) {
      setState(() => error = 'Choose one video for your Reel.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      progress = null;
    });
    try {
      await widget.store.rpc('write', {
        'p_id': id,
        'p_kind': kind,
        'p_body': body.text,
        'p_media': media,
        'p_audience': audience,
        'p_draft': draft,
      });
      saved = true;
      dirty = false;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> close() async {
    if (busy) return;
    if (dirty && !saved) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Use Save draft to keep this content. Uploaded files may remain until storage cleanup.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(kind == 'reel' ? 'Create Reel' : 'Create post'),
        leading: IconButton(
          onPressed: busy ? null : close,
          icon: const Icon(Icons.close),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'post',
                    label: Text('Post'),
                    icon: Icon(Icons.edit_note),
                  ),
                  ButtonSegment(
                    value: 'reel',
                    label: Text('Reel'),
                    icon: Icon(Icons.play_circle_outline),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: busy || media.isNotEmpty
                    ? null
                    : (value) => setState(() {
                        kind = value.first;
                        dirty = true;
                      }),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: body,
                enabled: !busy,
                minLines: 4,
                maxLines: 10,
                maxLength: 4000,
                decoration: const InputDecoration(
                  hintText:
                      'Share a thought… Add #hashtags, @username or !community_handle.',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: audience,
                items: const [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text('Public · signed-in Pulse users'),
                  ),
                  DropdownMenuItem(
                    value: 'followers',
                    child: Text('Approved followers'),
                  ),
                  DropdownMenuItem(
                    value: 'private',
                    child: Text('Private · only me'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        audience = value!;
                        dirty = true;
                      }),
              ),
              const SizedBox(height: 16),
              const Text(
                'Private accounts restrict posts to approved followers.',
              ),
              for (final item in media)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 220,
                        child:
                            item['kind'] == 'image' ||
                                item['cover_path'] != null
                            ? SocialImage(
                                store: widget.store,
                                path: item['cover_path'] ?? item['path'],
                              )
                            : SocialInlineVideo(
                                store: widget.store,
                                postId: id,
                                path: item['path'],
                                recordView: false,
                                autoplay: false,
                              ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (item['kind'] == 'video')
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.videocam_outlined),
                            ),
                          IconButton(
                            tooltip: 'Remove from post',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    media.remove(item);
                                    dirty = true;
                                  }),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : capture,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Open camera'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  kind == 'reel' ? 'Choose video' : 'Add photo or video',
                ),
              ),
              if (busy) ...[
                LinearProgressIndicator(value: progress),
                Text(
                  total > completed
                      ? 'Uploading… ${((progress ?? 0) * 100).round()}%'
                      : 'Saving to Pulse…',
                ),
              ],
              if (error != null)
                Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : () => submit(false),
                child: const Text('Publish'),
              ),
              TextButton(
                onPressed: busy ? null : () => submit(true),
                child: const Text('Save draft'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
