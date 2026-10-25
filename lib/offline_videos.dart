import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

Future<Directory> offlineVideoDirectory(String user) async {
  final root = await getApplicationSupportDirectory();
  return Directory('${root.path}/pulse-offline/$user');
}

Future<void> keepOfflineVideo(String user, File source, String name) async {
  final dir = await offlineVideoDirectory(user);
  await dir.create(recursive: true);
  var limit = 512 * 1024 * 1024;
  try {
    final p =
        jsonDecode(await File('${dir.path}/settings.json').readAsString())
            as Map;
    limit = (p['limit'] as num).toInt() * 1024 * 1024;
  } catch (_) {}
  var used = 0;
  await for (final entry in dir.list()) {
    if (entry is File && entry.path.endsWith('.mp4'))
      used += await entry.length();
  }
  if (used + await source.length() > limit)
    throw StateError(
      'Offline storage limit reached. Remove videos or increase the limit.',
    );
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  await source.copy(
    '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-$safe',
  );
}

class PulseOfflineVideos extends StatefulWidget {
  const PulseOfflineVideos({super.key, required this.user});
  final String user;
  @override
  State<PulseOfflineVideos> createState() => _PulseOfflineVideosState();
}

class _PulseOfflineVideosState extends State<PulseOfflineVideos> {
  List<File> files = [];
  String query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final dir = await offlineVideoDirectory(widget.user);
    final result = await dir.exists()
        ? await dir
              .list()
              .where((f) => f is File && f.path.endsWith('.mp4'))
              .cast<File>()
              .toList()
        : <File>[];
    result.sort((a, b) => b.path.compareTo(a.path));
    if (mounted) setState(() => files = result);
  }

  String name(File f) => f.uri.pathSegments.last
      .replaceFirst(RegExp(r'^\d+-'), '')
      .replaceAll('_', ' ');
  @override
  Widget build(BuildContext context) {
    final visible = files
        .where((f) => name(f).toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Offline videos')),
      body: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.offline_bolt),
            title: Text('Saved on this device'),
            subtitle: Text(
              'Playback and search work without data. New videos and online interactions need internet.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search downloaded video names',
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      files.isEmpty
                          ? 'Download a permitted video to watch it here.'
                          : 'No matching videos',
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (c, i) {
                      final file = visible[i];
                      return ListTile(
                        leading: const Icon(Icons.play_circle_fill),
                        title: Text(name(file)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => _OfflinePlayer(file: file),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove offline copy',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await file.delete();
                            await load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OfflinePlayer extends StatefulWidget {
  const _OfflinePlayer({required this.file});
  final File file;
  @override
  State<_OfflinePlayer> createState() => _OfflinePlayerState();
}

class _OfflinePlayerState extends State<_OfflinePlayer> {
  late final Player player;
  late final VideoController controller;
  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.open(Media(widget.file.path));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offline video')),
    body: Video(controller: controller, fit: BoxFit.contain),
  );
}
