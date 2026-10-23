import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'media.dart';
import 'social_repository.dart';
import 'social_media.dart';
import 'social_preview.dart';
import 'media_picker.dart';
import 'chat_camera.dart';
import 'composer_clip.dart';
import 'channels.dart';

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
  late bool allowDownloads;
  final captionFocus = FocusNode();
  final media = <SocialRow>[];
  final staged = <String, PulseStudioResult>{};
  Directory? workspace;
  int selected = 0;
  bool busy = false, dirty = false, saved = false;
  String? error;
  String stage = 'Preparing your post';
  double? progress;
  @override
  void initState() {
    super.initState();
    id = widget.draft?['id'] ?? const Uuid().v4();
    body = TextEditingController(text: widget.draft?['body'] ?? '');
    kind = widget.draft?['kind'] ?? (widget.reel ? 'reel' : 'post');
    audience = widget.draft?['audience'] ?? 'public';
    allowDownloads = widget.draft?['allow_download'] != false;
    media.addAll(
      (widget.draft?['media'] as List? ?? []).map(
        (x) => Map<String, dynamic>.from(x as Map),
      ),
    );
    body.addListener(() {
      if (mounted) setState(() => dirty = true);
    });
  }

  @override
  void dispose() {
    body.dispose();
    captionFocus.dispose();
    final dir = workspace;
    if (dir != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dir.delete(recursive: true).catchError((_) => dir);
      });
    super.dispose();
  }

  Future<Directory> workingDirectory() async => workspace ??=
      await (await getTemporaryDirectory()).createTemp('pulse-compose-');
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
      if (result != null && mounted)
        await prepare(PulsePickedMedia(result.file, owned: true));
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (result != null) {
        try {
          await result.file.delete();
        } catch (_) {}
      }
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
          builder: (_) =>
              PulseMediaPicker(videoOnly: kind == 'reel', remaining: null),
        ),
      );
      if (selections == null) return;
      try {
        for (final item in selections) {
          if (!mounted) break;
          await prepare(item);
        }
      } finally {
        for (final item in selections.where((p) => p.owned)) {
          try {
            await item.file.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> prepare(PulsePickedMedia input, {int? replace}) async {
    final video = input.video;
    if (replace == null &&
        media.isNotEmpty &&
        (video || media.first['kind'] == 'video'))
      throw SocialFailure(
        'Use multiple photos or a single video. Remove the current media to switch.',
      );
    if (await input.file.length() > 2147483648)
      throw SocialFailure('This file exceeds the 2 GB hosting maximum.');
    if (!mounted) return;
    final result = await Navigator.push<PulseStudioResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialSelectionPreview(
          file: input.file,
          video: video,
          caption: body.text,
        ),
      ),
    );
    if (result == null) return;
    try {
      if (!mounted) return;
      final directory = await workingDirectory();
      final name = result.file.uri.pathSegments.last.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = await result.file.copy(
        '${directory.path}/${const Uuid().v4()}-$name',
      );
      if (!mounted) {
        try {
          await file.delete();
        } catch (_) {}
        return;
      }
      final key = 'staged:${const Uuid().v4()}';
      final item = <String, dynamic>{
        'path': key,
        'kind': video ? 'video' : 'image',
        'mime': mimeFor(file.path),
        'name': name,
      };
      setState(() {
        staged[key] = PulseStudioResult(file, cover: result.cover);
        if (replace == null) {
          media.add(item);
          selected = media.length - 1;
        } else {
          media[replace] = item;
          selected = replace;
        }
        if (result.caption != null) body.text = result.caption!;
        dirty = true;
        error = null;
      });
    } finally {
      if (result.file.path != input.file.path) {
        try {
          await result.file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> editSelected() async {
    if (busy || media.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      stage = 'Opening Studio';
    });
    try {
      final item = media[selected];
      var file = staged[item['path']]?.file;
      if (file == null) {
        final dir = await workingDirectory();
        file = File(
          '${dir.path}/${const Uuid().v4()}-${item['name'] ?? 'media.mp4'}',
        );
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        try {
          final response = await (await client.getUrl(
            Uri.parse(await widget.store.signed(item['path'], renew: true)),
          )).close().timeout(const Duration(seconds: 20));
          if (response.statusCode != 200)
            throw SocialFailure('Media is unavailable. Please retry.');
          final sink = file.openWrite();
          int bytes = 0;
          try {
            await for (final chunk in response.timeout(
              const Duration(seconds: 20),
            )) {
              bytes += chunk.length;
              if (bytes > 2147483648)
                throw SocialFailure('Media exceeds the hosting maximum.');
              sink.add(chunk);
            }
          } finally {
            await sink.close();
          }
        } finally {
          client.close(force: true);
        }
      }
      if (mounted) await prepare(PulsePickedMedia(file), replace: selected);
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit(bool draft) async {
    if (busy) return;
    if (body.text.trim().isEmpty && media.isEmpty) {
      setState(() => error = 'Add a caption, photos or a video first.');
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
      stage = 'Preparing upload';
    });
    try {
      for (var i = 0; i < media.length; i++) {
        final item = media[i];
        final local = staged[item['path']];
        if (local == null) continue;
        if (item['path'].toString().startsWith('staged:')) {
          setState(() {
            stage = 'Uploading ${i + 1} of ${media.length}';
            progress = 0;
          });
          final old = item['path'] as String;
          final path = await widget.store.upload(
            local.file,
            item['name'],
            id,
            progress: (v) {
              if (mounted) setState(() => progress = v);
            },
          );
          item['path'] = path;
          staged.remove(old);
          staged[path] = local;
        }
        if (local.cover != null && item['cover_path'] == null) {
          final dir = await workingDirectory();
          final file = File('${dir.path}/${const Uuid().v4()}-cover.jpg');
          await file.writeAsBytes(local.cover!);
          item['cover_path'] = await widget.store.upload(
            file,
            'video-cover.jpg',
            id,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        stage = draft ? 'Saving draft' : 'Publishing your post';
        progress = null;
      });
      await widget.store.rpc('write_options', {
        'p_id': id,
        'p_kind': kind,
        'p_body': body.text,
        'p_media': media,
        'p_audience': audience,
        'p_draft': draft,
        'p_allow_download': allowDownloads,
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

  void insertCaption(String token) {
    final selection = body.selection;
    final start = selection.isValid ? selection.start : body.text.length;
    final end = selection.isValid ? selection.end : body.text.length;
    final prefix = start > 0 && body.text[start - 1] != ' ' ? ' ' : '';
    final value = '$prefix$token';
    if (body.text.length - (end - start) + value.length > 4000) return;
    body.value = TextEditingValue(
      text: body.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    captionFocus.requestFocus();
  }

  String get audienceLabel => switch (audience) {
    'followers' => 'Followers',
    'private' => 'Only me',
    _ => 'Everyone on Pulse',
  };
  IconData get audienceIcon => switch (audience) {
    'followers' => Icons.people_outline,
    'private' => Icons.lock_outline,
    _ => Icons.public,
  };
  Future<void> chooseAudience() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Who can watch?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          for (final choice in [
            (
              'public',
              'Everyone on Pulse',
              'Signed-in users; private accounts still require approval.',
              Icons.public,
            ),
            (
              'followers',
              'Followers',
              'Your approved followers.',
              Icons.people_outline,
            ),
            (
              'private',
              'Only me',
              'Keep this post private.',
              Icons.lock_outline,
            ),
          ])
            ListTile(
              leading: Icon(choice.$4),
              title: Text(choice.$2),
              subtitle: Text(choice.$3),
              trailing: audience == choice.$1
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => Navigator.pop(c, choice.$1),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
    if (value != null && mounted)
      setState(() {
        audience = value;
        dirty = true;
      });
  }

  void removeSelected() {
    setState(() {
      media.removeAt(selected);
      selected = math.max(0, math.min(selected, media.length - 1));
      dirty = true;
    });
  }

  Widget previewItem(int index, {bool thumbnail = false}) {
    final item = media[index];
    final local = staged[item['path']];
    if (local != null) {
      if (item['kind'] == 'image')
        return Image.file(
          local.file,
          fit: BoxFit.contain,
          cacheWidth: thumbnail ? 160 : 1100,
        );
      if (thumbnail)
        return local.cover != null
            ? Image.memory(local.cover!, fit: BoxFit.cover, cacheWidth: 160)
            : const Icon(Icons.movie_outlined, color: Colors.white);
      return PulseComposerClip(
        key: ValueKey(item['path']),
        file: local.file,
        cover: local.cover,
      );
    }
    if (item['kind'] == 'image' || thumbnail && item['cover_path'] != null)
      return SocialImage(
        store: widget.store,
        path: item['cover_path'] ?? item['path'],
        fit: thumbnail ? BoxFit.cover : BoxFit.contain,
        cacheWidth: thumbnail ? 160 : 1100,
      );
    if (thumbnail) return const Icon(Icons.movie_outlined, color: Colors.white);
    return SocialInlineVideo(
      key: ValueKey(item['path']),
      store: widget.store,
      postId: id,
      path: item['path'],
      coverPath: item['cover_path'],
      recordView: false,
      autoplay: false,
    );
  }

  Widget preview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: media.isEmpty ? 4 / 4.8 : 4 / 4.3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xff132f34),
                      Color(0xff111621),
                      Color(0xff241c3c),
                    ],
                  ),
                ),
              ),
              if (media.isNotEmpty)
                previewItem(selected)
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .14),
                            ),
                          ),
                          child: const Icon(
                            Icons.video_collection_outlined,
                            size: 32,
                            color: Color(0xff8cebd7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Make it a moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Your story starts here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: busy ? null : pick,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Choose media'),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Row(
                  children: [
                    for (final value in ['post', 'reel'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(value == 'post' ? 'Post' : 'Reel'),
                          selected: kind == value,
                          onSelected: busy || media.isNotEmpty
                              ? null
                              : (_) => setState(() {
                                  kind = value;
                                  dirty = true;
                                }),
                        ),
                      ),
                    const Spacer(),
                    if (media.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${selected + 1}/${media.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              if (media.isNotEmpty)
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : editSelected,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Edit in Studio'),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (media.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 84,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: media.length,
            onReorder: (from, to) {
              if (busy) return;
              setState(() {
                final active = media[selected];
                if (to > from) to--;
                final item = media.removeAt(from);
                media.insert(to, item);
                selected = media.indexOf(active);
                dirty = true;
              });
            },
            itemBuilder: (_, i) => Padding(
              key: ValueKey(media[i]['path']),
              padding: const EdgeInsets.only(right: 8),
              child: ReorderableDelayedDragStartListener(
                index: i,
                enabled: !busy,
                child: InkWell(
                  onTap: busy ? null : () => setState(() => selected = i),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 68,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected == i
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        previewItem(i, thumbnail: true),
                        Positioned(
                          left: 4,
                          top: 4,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: Colors.black54,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            media.length > 1
                ? 'Hold a photo to reorder · tap to preview'
                : 'Preview your edit before posting',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy || media.any((m) => m['kind'] == 'video')
                  ? null
                  : pick,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy || media.isNotEmpty ? null : capture,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Camera'),
            ),
          ),
          if (media.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Remove selected media',
              onPressed: busy ? null : removeSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    ],
  );
  Widget details() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'The finishing touches',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'A little context goes a long way.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: body,
        focusNode: captionFocus,
        enabled: !busy,
        minLines: 3,
        maxLines: 7,
        maxLength: 4000,
        decoration: InputDecoration(
          hintText: 'Tell your story…',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(18),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          ActionChip(
            label: const Text('# Hashtag'),
            onPressed: busy ? null : () => insertCaption('#'),
          ),
          ActionChip(
            label: const Text('@ Mention'),
            onPressed: busy ? null : () => insertCaption('@'),
          ),
          ActionChip(
            label: const Text('! Community'),
            onPressed: busy ? null : () => insertCaption('!'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            ListTile(
              leading: Icon(audienceIcon),
              title: const Text('Who can watch'),
              subtitle: Text(audienceLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : chooseAudience,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile.adaptive(
              title: const Text('Allow video downloads'),
              subtitle: const Text('Let viewers save or export this video.'),
              value: allowDownloads,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      allowDownloads = v;
                      dirty = true;
                    }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Private accounts share with approved followers. Your changes stay unpublished until you post.',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close composer',
          onPressed: busy ? null : close,
          icon: const Icon(Icons.close),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PULSE STUDIO',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Create a moment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Go LIVE',
            onPressed: busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Choose a channel for LIVE'),
                        ),
                        body: ChannelsScreen(repo: widget.store.repo),
                      ),
                    ),
                  ),
            icon: const Icon(Icons.live_tv_rounded),
          ),
          TextButton(
            onPressed: busy ? null : () => submit(true),
            child: const Text('Save draft'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? stage
                      : '$stage · ${(progress! * 100).round()}%',
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => submit(true),
                      icon: const Icon(Icons.drafts_outlined, size: 18),
                      label: const Text('Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => submit(false),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: Text(kind == 'reel' ? 'Post Reel' : 'Post now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (c, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: box.maxWidth >= 840
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: preview()),
                        const SizedBox(width: 32),
                        Expanded(flex: 5, child: details()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        preview(),
                        const SizedBox(height: 28),
                        details(),
                        const SizedBox(height: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
