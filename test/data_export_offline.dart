import 'dart:convert';
import 'dart:io';
import '../lib/data_export.dart';

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('pulse-export-');
  final file = File('${directory.path}/data.json');
  final rows = List<ExportRow>.generate(
    631,
    (i) => {
      'id': i.toString().padLeft(5, '0'),
      'body': 'Message $i: "hello"\n💚',
    },
  );
  int pages = 0, lastCount = 0;
  try {
    await PulseDataExport().write(
      file,
      'fixture-account',
      [
        ExportSection('messages', (after, limit) async {
          pages++;
          require(limit == 250, 'Page bound changed');
          return rows
              .where(
                (r) =>
                    after == null || (r['id'] as String).compareTo(after) > 0,
              )
              .take(limit)
              .toList();
        }),
        ExportSection('empty', (_, __) async => []),
      ],
      cancelled: () => false,
      progress: (_, n) {
        if (n > 0) lastCount = n;
      },
    );
    final result = jsonDecode(await file.readAsString()) as Map;
    require(pages == 3 && lastCount == 631, 'Pagination incomplete');
    require(
      jsonEncode(result['data']['messages']) == jsonEncode(rows),
      'Content changed or duplicated',
    );
    require((result['data']['empty'] as List).isEmpty, 'Empty section invalid');
    require(result['includes_media_bytes'] == false, 'Scope incorrect');
    // An existing destination must not be truncated.
    try {
      await PulseDataExport().write(
        file,
        'fixture',
        [],
        cancelled: () => false,
      );
      throw StateError('Existing file overwritten');
    } on StateError catch (e) {
      require(
        e.message == 'Export destination exists',
        'Unexpected overwrite result',
      );
    }
    require(
      (jsonDecode(await file.readAsString()) as Map)['account_id'] ==
          'fixture-account',
      'Existing export damaged',
    );
    await file.delete();
    bool cancel = false;
    try {
      await PulseDataExport().write(
        file,
        'fixture',
        [ExportSection('messages', (_, __) async => rows.take(250).toList())],
        cancelled: () => cancel,
        progress: (_, __) => cancel = true,
      );
      throw StateError('Cancellation ignored');
    } on ExportCancelled {}
    require(!await file.exists(), 'Cancelled export leaked partial messages');
    // Reject non-advancing cursors rather than repeating pages indefinitely.
    try {
      await PulseDataExport().write(file, 'fixture', [
        ExportSection(
          'bad',
          (_, __) async => [
            {'id': 'b'},
            {'id': 'a'},
          ],
        ),
      ], cancelled: () => false);
      throw StateError('Invalid cursor accepted');
    } on StateError catch (e) {
      require(
        e.message == 'Invalid export cursor',
        'Unexpected cursor failure',
      );
    }
    require(!await file.exists(), 'Failed export retained partial data');
    try {
      await PulseDataExport().write(file, 'fixture', [
        ExportSection('oversized', (_, __) async => rows),
      ], cancelled: () => false);
      throw StateError('Oversized page accepted');
    } on StateError catch (e) {
      require(e.message == 'Export page too large', 'Unexpected page failure');
    }
    require(!await file.exists(), 'Oversized export retained partial data');
    print(
      'PASS: bounded export pagination, exact Unicode content, cancellation cleanup, existing-file protection and invalid-cursor rejection',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
