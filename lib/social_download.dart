import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'native_editor.dart';
import 'social_repository.dart';

Future<void> downloadPulsePost(
  BuildContext context,
  SocialStore store,
  String id,
) async {
  final fresh = await store.post(id);
  if (fresh == null) throw SocialFailure('This post is no longer available.');
  final media = (fresh['media'] as List).cast<Map>();
  if (media.isEmpty) throw SocialFailure('This is a text-only post.');
  int selected = 0;
  if (media.length > 1) {
    if (!context.mounted) return;
    final index = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose a photo to download')),
            for (var i = 0; i < media.length; i++)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text('Photo ${i + 1}'),
                onTap: () => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
    if (index == null) return;
    selected = index;
  }
  final item = media[selected];
  String? directory;
  if (Platform.isWindows) {
    directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Save Pulse media',
    );
    if (directory == null) return;
  }
  final safe =
      (item['name'] ??
              'Pulse-${item['kind'] == 'video' ? 'video.mp4' : 'photo.jpg'}')
          .toString()
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final temp = await getTemporaryDirectory();
  final target = File('${directory ?? temp.path}/${const Uuid().v4()}-$safe');
  final progress = ValueNotifier<double?>(null);
  bool cancel = false;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  if (!context.mounted) {
    client.close();
    progress.dispose();
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Downloading'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text(value == null ? 'Connecting…' : '${(value * 100).round()}%'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancel = true;
              client.close(force: true);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
  final dialog = navigator.push(route);
  try {
    final url = Uri.parse(await store.signed(item['path'], renew: true));
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
          progress.value = (bytes / response.contentLength).clamp(0, 1);
      }
    } finally {
      await sink.close();
    }
    if (cancel) throw SocialFailure('Download cancelled.');
    if (bytes == 0 ||
        (response.contentLength >= 0 && bytes != response.contentLength))
      throw SocialFailure('Download incomplete. Please retry.');
    // Recheck access before making the completed local file visible.
    if (await store.post(id) == null)
      throw SocialFailure('Access to this post changed.');
    if (Platform.isAndroid) {
      await NativePulseEditor.saveDownload(target, safe, item['mime']);
      await target.delete();
    }
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
    if (await target.exists()) await target.delete();
    rethrow;
  } finally {
    client.close(force: true);
    if (route.isActive) navigator.removeRoute(route);
    await dialog;
    progress.dispose();
  }
}
