import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'offline_videos.dart';
import 'social_repository.dart';
import 'social_download.dart';
import 'package:path_provider/path_provider.dart';

Future<File> offlinePreferences(String user) async =>
    File('${(await offlineVideoDirectory(user)).path}/settings.json');
Future<Map<String, dynamic>> readOfflinePreferences(String user) async {
  try {
    return Map<String, dynamic>.from(
      jsonDecode(await (await offlinePreferences(user)).readAsString()) as Map,
    );
  } catch (_) {
    return {'count': 10, 'wifi': true, 'limit': 512};
  }
}

class PulseOfflineSettings extends StatefulWidget {
  const PulseOfflineSettings({super.key, required this.store});
  final SocialStore store;
  @override
  State<PulseOfflineSettings> createState() => _PulseOfflineSettingsState();
}

class _PulseOfflineSettingsState extends State<PulseOfflineSettings> {
  Map<String, dynamic> prefs = {'count': 10, 'wifi': true, 'limit': 512};
  bool busy = false, cancel = false;
  int saved = 0;
  String status = '';
  @override
  void initState() {
    super.initState();
    readOfflinePreferences(widget.store.uid).then((p) {
      if (mounted) setState(() => prefs = p);
    });
  }

  Future<void> save() async {
    final f = await offlinePreferences(widget.store.uid);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(prefs));
  }

  Future<void> batch() async {
    if (busy) return;
    setState(() {
      busy = true;
      cancel = false;
      saved = 0;
      status = 'Finding permitted videos…';
    });
    try {
      if (prefs['wifi'] == true) {
        final interfaces = await NetworkInterface.list();
        if (!interfaces.any(
          (i) =>
              RegExp(r'wlan|wi-fi|wifi', caseSensitive: false).hasMatch(i.name),
        ))
          throw StateError(
            'Wi-Fi could not be confirmed. Connect to Wi-Fi or turn Wi-Fi only off.',
          );
      }
      SocialRow? cursor;
      for (
        var page = 0;
        page < 20 && saved < (prefs['count'] as num).toInt() && !cancel;
        page++
      ) {
        final rows = await widget.store.feed(kind: 'reel', cursor: cursor);
        if (rows.isEmpty) break;
        cursor = rows.last;
        for (final post in rows) {
          if (cancel || !mounted || saved >= (prefs['count'] as num).toInt())
            break;
          if (mounted)
            setState(
              () => status = 'Downloading ${saved + 1} of ${prefs['count']}…',
            );
          try {
            await downloadPulsePost(
              context,
              widget.store,
              post['id'],
              offlineOnly: true,
            );
            saved++;
          } catch (_) {
            /* Skip restricted, removed or failed clips. */
          }
        }
      }
      if (mounted)
        setState(
          () => status =
              '${cancel ? 'Stopped' : 'Finished'} · $saved videos saved. Unavailable videos were skipped.',
        );
    } catch (e) {
      if (mounted)
        setState(() => status = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear offline videos and cache?'),
        content: const Text(
          'Removes this account’s offline copies and temporary video preloads. Messages, login, drafts and files exported to Downloads are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final dir = await offlineVideoDirectory(widget.store.uid);
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.mp4')) await f.delete();
      }
    }
    final temp = await getTemporaryDirectory();
    await for (final f in temp.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('pulse-next-')) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted)
      setState(() => status = 'Offline videos and media cache cleared.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offline videos & storage')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          initialValue: prefs['count'] as int,
          decoration: const InputDecoration(labelText: 'Videos per batch'),
          items: [10, 20, 50, 100]
              .map((n) => DropdownMenuItem(value: n, child: Text('$n videos')))
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  setState(() => prefs['count'] = v!);
                  save();
                },
        ),
        SwitchListTile(
          title: const Text('Wi-Fi only'),
          value: prefs['wifi'] == true,
          onChanged: busy
              ? null
              : (v) {
                  setState(() => prefs['wifi'] = v);
                  save();
                },
        ),
        DropdownButtonFormField<int>(
          initialValue: prefs['limit'] as int,
          decoration: const InputDecoration(labelText: 'Offline storage limit'),
          items: [256, 512, 1024]
              .map((n) => DropdownMenuItem(value: n, child: Text('$n MB')))
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  setState(() => prefs['limit'] = v!);
                  save();
                },
        ),
        const ListTile(
          subtitle: Text(
            'Downloads use data. File sizes vary; the library stays within your selected storage limit. Only creator-permitted videos are saved.',
          ),
        ),
        FilledButton.icon(
          onPressed: busy ? null : batch,
          icon: const Icon(Icons.download),
          label: const Text('Download videos for offline'),
        ),
        if (busy)
          TextButton(
            onPressed: () {
              cancel = true;
              for (final job in pulseDownloads.value.values) {
                job.cancel();
              }
            },
            child: const Text('Cancel downloads'),
          ),
        Text(status),
        ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('Watch & manage offline videos'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PulseOfflineVideos(user: widget.store.uid),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear cache & offline videos'),
          onTap: busy ? null : clear,
        ),
      ],
    ),
  );
}
