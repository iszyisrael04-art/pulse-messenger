import 'dart:convert';
import 'dart:io';
import '../lib/social_upload.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('pulse-tus-test-');
  final file = File('${dir.path}/fixture.mp4');
  final bytes = List<int>.generate(
    PulseTusUploader.chunkSize + 123,
    (i) => i % 251,
  );
  await file.writeAsBytes(bytes);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var offset = 0, patches = 0, recovered = false;
  final received = <int>[];
  final subscription = server.listen((request) async {
    if (request.headers.value('authorization') != 'Bearer fixture')
      throw StateError('Missing auth');
    if (request.method == 'POST') {
      final metadata = request.headers.value('upload-metadata')!;
      if (!metadata.contains(base64Encode(utf8.encode('pulse-social'))))
        throw StateError('Metadata');
      request.response.statusCode = 201;
      request.response.headers.set('location', '/upload/fixture');
    } else if (request.method == 'HEAD') {
      recovered = true;
      request.response.headers.set('upload-offset', '$offset');
    } else if (request.method == 'PATCH') {
      patches++;
      if (request.headers.value('upload-offset') != '$offset')
        throw StateError('Wrong offset');
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      if (body.length > PulseTusUploader.chunkSize)
        throw StateError('Unbounded buffer');
      received.addAll(body);
      offset += body.length;
      // First chunk was accepted but the client received a transient failure.
      request.response.statusCode = patches == 1 ? 503 : 204;
      request.response.headers.set('upload-offset', '$offset');
    }
    await request.response.close();
  });
  try {
    double progress = 0;
    final updates = <double>[];
    await PulseTusUploader(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/upload'),
      token: () async => 'fixture',
    ).upload(
      file,
      'owner/post/video.mp4',
      'video/mp4',
      progress: (v) {
        progress = v;
        updates.add(v);
      },
    );
    if (!recovered ||
        patches != 2 ||
        progress != 1 ||
        updates.first != 0 ||
        updates.where((v) => v > 0 && v < 1).length < 10 ||
        received.length != bytes.length)
      throw StateError('Resume failed');
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != received[i]) throw StateError('Corrupt upload');
    }
    print(
      'PASS: bounded chunks, auth, metadata, uncertain-response recovery, progress and byte integrity',
    );
  } finally {
    await subscription.cancel();
    await server.close(force: true);
    await dir.delete(recursive: true);
  }
}
