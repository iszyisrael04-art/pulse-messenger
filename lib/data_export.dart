import 'dart:convert';
import 'dart:io';

typedef ExportRow = Map<String, dynamic>;
typedef ExportPage = Future<List<ExportRow>> Function(String? after, int limit);

class ExportSection {
  const ExportSection(this.name, this.page, {this.cursor = 'id'});
  final String name, cursor;
  final ExportPage page;
}

class ExportCancelled implements Exception {}

/// Streams one bounded page at a time. Contains no credentials or media bytes.
class PulseDataExport {
  static const pageSize = 250;
  Future<void> write(
    File output,
    String user,
    List<ExportSection> sections, {
    required bool Function() cancelled,
    void Function(String section, int rows)? progress,
  }) async {
    if (await output.exists()) throw StateError('Export destination exists');
    final sink = output.openWrite();
    bool complete = false;
    try {
      sink.write('{"format":"pulse-account-export-v1","account_id":');
      sink.write(jsonEncode(user));
      sink.write(',"exported_at":');
      sink.write(jsonEncode(DateTime.now().toUtc().toIso8601String()));
      sink.write(',"includes_media_bytes":false,"data":{');
      var firstSection = true;
      for (final section in sections) {
        if (cancelled()) throw ExportCancelled();
        if (!firstSection) sink.write(',');
        firstSection = false;
        sink.write('${jsonEncode(section.name)}:[');
        String? after;
        int count = 0;
        while (true) {
          if (cancelled()) throw ExportCancelled();
          final rows = await section.page(after, pageSize);
          if (rows.length > pageSize) throw StateError('Export page too large');
          for (final row in rows) {
            if (cancelled()) throw ExportCancelled();
            final cursor = row[section.cursor];
            if (cursor is! String ||
                cursor.isEmpty ||
                (after != null && cursor.compareTo(after) <= 0)) {
              throw StateError('Invalid export cursor');
            }
            if (count > 0) sink.write(',');
            sink.write(jsonEncode(row));
            after = cursor;
            count++;
          }
          await sink.flush();
          progress?.call(section.name, count);
          if (rows.length < pageSize) break;
        }
        sink.write(']');
      }
      if (cancelled()) throw ExportCancelled();
      sink.write('}}');
      await sink.flush();
      complete = true;
    } finally {
      try {
        await sink.close();
      } finally {
        if (!complete && await output.exists()) await output.delete();
      }
    }
  }
}
