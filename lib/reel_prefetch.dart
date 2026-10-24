import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// One next clip, bounded to 24 MiB. Never plays audio or takes player focus.
class PulseReelPrefetch {
  static const limit = 24 * 1024 * 1024;
  HttpClient? client;
  File? file;
  String? path;
  int generation = 0;
  File? take(String source) {
    if (source != path) return null;
    final result = file;
    file = null;
    path = null;
    return result;
  }

  Future<void> clear() async {
    generation++;
    client?.close(force: true);
    client = null;
    final old = file;
    file = null;
    path = null;
    if (old != null) {
      try {
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
  }

  Future<void> warm(String source, Future<String> Function() signed) async {
    if (path == source) return;
    await clear();
    final ticket = generation;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    client = http;
    File? candidate;
    try {
      final uri = Uri.parse(await signed());
      if (ticket != generation) return;
      final request = await http.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200 || response.contentLength > limit) return;
      final directory = await getTemporaryDirectory();
      candidate = File(
        '${directory.path}/pulse-next-${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final sink = candidate.openWrite();
      int bytes = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 12),
        )) {
          if (ticket != generation || bytes + chunk.length > limit) return;
          sink.add(chunk);
          bytes += chunk.length;
        }
      } finally {
        await sink.close();
      }
      if (ticket != generation ||
          bytes == 0 ||
          response.contentLength >= 0 && bytes != response.contentLength)
        return;
      file = candidate;
      path = source;
      candidate = null;
    } catch (_) {
      // Prefetch is optional: regular signed streaming remains available.
    } finally {
      http.close(force: true);
      if (client == http) client = null;
      if (candidate != null && await candidate.exists())
        await candidate.delete();
    }
  }
}
