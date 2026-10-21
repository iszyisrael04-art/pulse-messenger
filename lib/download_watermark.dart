import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Build a small logo/creator badge once; native encoders composite it per frame.
Future<void> buildPulseDownloadBadge(File output, String? username) async {
  final data = await rootBundle.load('assets/branding/pulse.png');
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    targetWidth: 72,
  );
  final frame = await codec.getNextFrame();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 320, 96),
      const Radius.circular(16),
    ),
    Paint()..color = const Color(0xaa080b17),
  );
  canvas.drawImageRect(
    frame.image,
    Rect.fromLTWH(
      0,
      0,
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    ),
    const Rect.fromLTWH(12, 12, 72, 72),
    Paint(),
  );
  void text(String value, double size, double top, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 212);
    painter.paint(canvas, Offset(96, top));
  }

  text('pulse', 30, 10, FontWeight.w800);
  text(
    username == null || username.isEmpty ? 'Made on Pulse' : '@$username',
    18,
    54,
    FontWeight.w500,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 96);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Could not prepare download watermark');
    await output.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
    frame.image.dispose();
    codec.dispose();
  }
}
