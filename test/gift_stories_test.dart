import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_stories.dart';

void main() {
  test(
    'Rocket lifts off, approaches moon and remains settled after contact',
    () {
      expect(
        pulseRocketPose(.2).position.dy,
        lessThan(pulseRocketPose(0).position.dy),
      );
      expect(pulseRocketPose(.5).angle, lessThan(-.2));
      final landing = pulseRocketPose(.85), settled = pulseRocketPose(1);
      expect(landing.landed, true);
      expect(settled.thrust, 0);
      expect(settled.angle, 0);
      expect(settled.position, landing.position);
      for (var i = 0; i <= 100; i++) {
        final p = pulseRocketPose(i / 100);
        expect(p.position.dx.isFinite && p.position.dy.isFinite, true);
        expect(p.scale, greaterThan(0));
      }
      expect(pulseCastleGate(.18), 0);
      expect(pulseCastleGate(.4), 1);
      expect(pulseKingWalk(.38), 0);
      expect(pulseKingWalk(.8), 1);
    },
  );

  testWidgets('Narrative scenes render takeoff, arrival, open gates and king', (
    tester,
  ) async {
    final shots = <ui.Image>[];
    final preview =
        Platform.environment['GITHUB_ACTIONS'] == 'true' &&
        Platform.environment['RUNNER_OS'] == 'Linux';
    final key = GlobalKey();
    for (final sku in ['rocket', 'castle']) {
      for (final phase in [.12, .55, .95]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 320,
                height: 568,
                child: RepaintBoundary(
                  key: key,
                  child: PulseGiftStoryScene(sku: sku, phase: phase),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$sku at $phase');
        if (preview) {
          final image = await tester.runAsync(
            () async =>
                (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: .5),
          );
          shots.add(image!);
        }
      }
    }
    if (preview) {
      // A single contact sheet is emitted for human visual QA in the CI log.
      final sheet = ui.PictureRecorder();
      final c = Canvas(sheet);
      for (var i = 0; i < shots.length; i++) {
        c.drawImage(
          shots[i],
          Offset((i % 3) * 160.0, (i ~/ 3) * 284.0),
          Paint(),
        );
      }
      final picture = sheet.endRecording();
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(480, 568);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final encoded = base64Encode(bytes!);
      for (var at = 0; at < encoded.length; at += 8000) {
        print(
          'PULSE_STORY_PREVIEW:${at ~/ 8000}:${encoded.substring(at, (at + 8000).clamp(0, encoded.length))}',
        );
      }
      picture.dispose();
      for (final shot in shots) {
        shot.dispose();
      }
    }
  });
}
