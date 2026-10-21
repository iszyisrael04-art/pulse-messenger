import 'dart:io';
import 'dart:typed_data';

class PulseStudioResult {
  PulseStudioResult(this.file, {this.cover, this.caption});
  final File file;
  final Uint8List? cover;
  final String? caption;
}
