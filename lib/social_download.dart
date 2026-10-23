import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'download_watermark.dart';
import 'package:share_plus/share_plus.dart';
import 'native_editor.dart';
import 'social_repository.dart';

Future<void> downloadPulsePost(
  BuildContext context,
  SocialStore store,
  String id, {
  bool external = false,
}) async {
  final fresh = await store.post(id);
  if (fresh == null) throw SocialFailure('This post is no longer available.');
  final media = (fresh['media'] as List).cast<Map>();
  final author = fresh['author'];
  final username = author is Map ? author['username']?.toString() : null;
  final text =
      '${fresh['body'] ?? ''}\n${username == null ? 'Shared from Pulse' : 'Shared from @$username on Pulse'}'
          .trim();
  if (media.isEmpty) {
    if (!external) throw SocialFailure('This is a text-only post.');
    await SharePlus.instance.share(ShareParams(text: text));
    return;
  }
  int selected = 0;
  if (media.length > 1) {
    if (!context.mounted) return;
    final index = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose media to export')),
            for (var i = 0; i < media.length; i++)
              ListTile(
                leading: Icon(
                  media[i]['kind'] == 'video'
                      ? Icons.movie_outlined
                      : Icons.image_outlined,
                ),
                title: Text(
                  '${media[i]['kind'] == 'video' ? 'Video' : 'Photo'} ${i + 1}',
                ),
                onTap: () => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
    if (index == null) return;
    selected = index;
  }
  await downloadPulseMedia(
    context,
    media[selected],
    username: username,
    externalText: external ? text : null,
    signedUrl: () => store.signed(media[selected]['path'], renew: true),
    stillAllowed: () async => await store.post(id) != null,
  );
}

/// Shared public-content export. A video is saved only after watermark succeeds.
Future<void> downloadPulseMedia(
  BuildContext context,
  Map item, {
  String? username,
  String? externalText,
  required Future<String> Function() signedUrl,
  required Future<bool> Function() stillAllowed,
}) async {
  final video = itemIsVideo(item);
  String? directory;
  if (Platform.isWindows && externalText == null) {
    directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Save Pulse media',
    );
    if (directory == null) return;
  }
  var safe = (item['name'] ?? (video ? 'Pulse-video.mp4' : 'Pulse-photo.jpg'))
      .toString()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final originalName = safe;
  if (video) safe = '${safe.replaceFirst(RegExp(r'\.[^.]*$'), '')}.mp4';
  final temp = await getTemporaryDirectory();
  final token = const Uuid().v4();
  final target = File('${temp.path}/pulse-$token-source-$originalName');
  final output = File('${temp.path}/pulse-$token.mp4');
  final badge = File('${temp.path}/pulse-$token-badge.png');
  final progress = ValueNotifier<double?>(null);
  final stage = ValueNotifier<String>('Downloading');
  bool cancel = false, watermarking = false;
  File? published;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  if (!context.mounted) {
    client.close();
    progress.dispose();
    stage.dispose();
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<String>(
        valueListenable: stage,
        builder: (_, label, __) => AlertDialog(
          title: Text(label),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 12),
                Text(
                  value == null ? 'Preparing…' : '${(value * 100).round()}%',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancel = true;
                client.close(force: true);
                if (watermarking)
                  unawaited(NativePulseEditor.cancel().catchError((_) {}));
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  final dialog = navigator.push(route);
  try {
    final url = Uri.parse(await signedUrl());
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != 200)
      throw SocialFailure('Download unavailable. Please retry.');
    final sink = target.openWrite();
    int bytes = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        if (cancel) throw SocialFailure('Download cancelled.');
        sink.add(chunk);
        await sink.flush();
        bytes += chunk.length;
        if (response.contentLength > 0)
          progress.value =
              (bytes / response.contentLength).clamp(0, 1) *
              (video ? .60 : .95);
      }
    } finally {
      await sink.close();
    }
    if (cancel) throw SocialFailure('Download cancelled.');
    if (bytes == 0 ||
        response.contentLength >= 0 && bytes != response.contentLength)
      throw SocialFailure('Download incomplete. Please retry.');
    if (!await stillAllowed())
      throw SocialFailure('Access to this post changed.');
    File ready = target;
    if (video) {
      stage.value = 'Adding Pulse watermark';
      progress.value = .60;
      await buildPulseDownloadBadge(badge, username);
      if (cancel) throw SocialFailure('Download cancelled.');
      watermarking = true;
      try {
        await NativePulseEditor.watermark(target, output, badge, (value) {
          if (!cancel) progress.value = .60 + value * .39;
        });
      } finally {
        watermarking = false;
      }
      ready = output;
    }
    if (cancel) throw SocialFailure('Download cancelled.');
    // Enforce current visibility after encoding, before publishing any file.
    if (!await stillAllowed())
      throw SocialFailure('Access to this post changed.');
    if (cancel) throw SocialFailure('Download cancelled.');
    if (externalText != null) {
      final shares = Directory('${temp.path}/pulse-shares');
      await shares.create(recursive: true);
      // Keep shared files alive for receiving apps; reclaim old exports later.
      await for (final entry in shares.list()) {
        if (entry is File &&
            DateTime.now().difference(await entry.lastModified()) >
                const Duration(days: 1)) {
          await entry.delete();
        }
      }
      final shared = await ready.copy('${shares.path}/$token-$safe');
      if (route.isActive) navigator.removeRoute(route);
      await dialog;
      await SharePlus.instance.share(
        ShareParams(
          text: externalText,
          files: [
            XFile(
              shared.path,
              mimeType: video
                  ? 'video/mp4'
                  : (item['mime'] ?? 'image/jpeg').toString(),
            ),
          ],
        ),
      );
      return;
    }
    stage.value = 'Saving';
    if (Platform.isAndroid) {
      await NativePulseEditor.saveDownload(
        ready,
        safe,
        video ? 'video/mp4' : (item['mime'] ?? 'image/jpeg').toString(),
      );
    } else if (Platform.isWindows) {
      published = File('$directory/$token-$safe');
      await ready.copy(published.path);
    } else {
      throw UnsupportedError('Downloads support Android and Windows.');
    }
    progress.value = 1;
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isAndroid
                ? 'Saved to Downloads/Pulse'
                : 'Saved to $directory',
          ),
        ),
      );
  } catch (_) {
    if (published != null && await published.exists()) await published.delete();
    rethrow;
  } finally {
    client.close(force: true);
    for (final file in [target, output, badge]) {
      if (await file.exists()) await file.delete();
    }
    if (route.isActive) navigator.removeRoute(route);
    await dialog;
    progress.dispose();
    stage.dispose();
  }
}

bool itemIsVideo(Map item) => item['kind'] == 'video';
