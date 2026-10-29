import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/legendary_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Portable alpha animations decode with transparent borders and original timing', () async {
    for (final entry in pulseLegendaryGifts.entries) {
      final bytes = await rootBundle.load('assets/gifts/${entry.key}.webp');
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
        targetWidth: 160,
      );
      var total = 0, maxAlpha = 0;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        total += frame.duration.inMilliseconds;
        if (i == 0 || i == codec.frameCount ~/ 2 || i == codec.frameCount - 1) {
          final raw = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final w = frame.image.width, h = frame.image.height;
          for (var x = 0; x < w; x++) {
            expect(
              raw[x * 4 + 3],
              lessThanOrEqualTo(3),
              reason: '${entry.key} top border',
            );
            expect(
              raw[((h - 1) * w + x) * 4 + 3],
              lessThanOrEqualTo(3),
              reason: '${entry.key} bottom border',
            );
          }
          for (var k = 3; k < raw.length; k += 4) {
            if (raw[k] > maxAlpha) maxAlpha = raw[k];
          }
        }
        frame.image.dispose();
      }
      expect(total, entry.value.durationMs, reason: entry.key);
      expect(
        maxAlpha,
        greaterThan(230),
        reason: 'Subject must stay opaque: ${entry.key}',
      );
      codec.dispose();
    }
  });
}
