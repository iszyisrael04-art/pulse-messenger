import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Native TUS transport: at most one 6 MiB chunk in memory. Retries recover
/// the server offset within this upload; process-restart recovery is not added.
class PulseTusUploader {
  PulseTusUploader({required this.endpoint, required this.token});
  final Uri endpoint;
  final Future<String> Function() token;
  static const chunkSize = 6 * 1024 * 1024;
  Future<void> upload(
    File file,
    String path,
    String mime, {
    void Function(double)? progress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final length = await file.length();
    final input = await file.open();
    Uri? uploadUrl;
    var offset = 0;
    try {
      Future<HttpClientResponse> request(
        String method,
        Uri uri, {
        Map<String, String> headers = const {},
        Uint8List? bytes,
      }) async {
        // Never forward a user's token to a redirect or arbitrary Location.
        if (uri.origin != endpoint.origin) {
          throw const HttpException('Unexpected upload server');
        }
        final r = await client.openUrl(method, uri);
        r.followRedirects = false;
        r.headers.set('Tus-Resumable', '1.0.0');
        r.headers.set('Authorization', 'Bearer ${await token()}');
        headers.forEach((k, v) => r.headers.set(k, v));
        if (bytes != null) {
          r.contentLength = bytes.length;
          r.add(bytes);
        }
        final response = await r.close().timeout(const Duration(minutes: 3));
        if (response.statusCode == 413) {
          await response.drain<void>();
          throw const HttpException(
            'Hosting storage file limit reached. The platform owner must enable larger files.',
          );
        }
        return response;
      }

      final metadata = {
        'bucketName': 'pulse-social',
        'objectName': path,
        'contentType': mime,
        'cacheControl': '3600',
      };
      final created = await request(
        'POST',
        endpoint,
        headers: {
          'Upload-Length': '$length',
          'Upload-Metadata': metadata.entries
              .map((e) => '${e.key} ${base64Encode(utf8.encode(e.value))}')
              .join(','),
        },
      );
      final location = created.headers.value('location');
      final status = created.statusCode;
      await created.drain<void>();
      if (status != 201 || location == null) {
        throw HttpException('Upload could not start ($status). Please retry.');
      }
      uploadUrl = endpoint.resolve(location);
      if (uploadUrl.origin != endpoint.origin)
        throw const HttpException('Unexpected upload server');
      var failures = 0;
      while (offset < length) {
        try {
          await input.setPosition(offset);
          final bytes = await input.read(
            (length - offset).clamp(0, chunkSize).toInt(),
          );
          if (bytes.isEmpty)
            throw const FileSystemException('Selected file changed');
          final response = await request(
            'PATCH',
            uploadUrl,
            headers: {
              'Content-Type': 'application/offset+octet-stream',
              'Upload-Offset': '$offset',
            },
            bytes: bytes,
          );
          final next = int.tryParse(
            response.headers.value('upload-offset') ?? '',
          );
          final code = response.statusCode;
          await response.drain<void>();
          if (code != 204 || next == null || next <= offset || next > length) {
            throw HttpException('Upload interrupted ($code)');
          }
          offset = next;
          failures = 0;
          progress?.call(offset / length);
        } catch (_) {
          if (++failures > 3) rethrow;
          await Future<void>.delayed(Duration(seconds: failures));
          final head = await request('HEAD', uploadUrl);
          final recovered = int.tryParse(
            head.headers.value('upload-offset') ?? '',
          );
          final code = head.statusCode;
          await head.drain<void>();
          if (code != 200 && code != 204 ||
              recovered == null ||
              recovered < 0 ||
              recovered > length) {
            throw const HttpException(
              'Upload cannot resume. Select the file again.',
            );
          }
          offset = recovered;
          progress?.call(offset / length);
        }
      }
    } finally {
      await input.close();
      client.close(force: true);
    }
  }
}
