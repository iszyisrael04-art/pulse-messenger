import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_face_anchor.dart';
import '../lib/gift_visuals.dart';
import '../lib/magic_hat.dart';

void main() {
  testWidgets('Wizard filter uses the detected head and hides on tracking loss', (tester) async {
    PulseFaceAnchor? face = const PulseFaceAnchor(Rect.fromLTWH(.3,.4,.25,.25), Size(480,854), .1);
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 360, height: 640,
      child: PulseHeadCrown(sku: 'wizard_filter', until: DateTime.now().add(const Duration(seconds: 12)),
        sample: () async => face, child: const ColoredBox(color: Colors.black)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PulseMagicHat), findsOneWidget);
    face = null;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(PulseMagicHat), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('Magic hats anchor their brim at the forehead and keep the face visible', () {
    const face = Rect.fromLTWH(100, 200, 80, 120);
    for (final sku in ['wizard_filter','witch_filter']) {
      final hat = pulseHeadGiftBounds(face, sku);
      expect(hat.center.dx, face.center.dx);
      expect(hat.width, 160);
      expect(hat.top, lessThan(face.top));
      expect(hat.bottom, lessThan(face.center.dy));
    }
  });
  test(
    'Face coordinates respect contained video letterboxing and front mirror',
    () {
      const a = PulseFaceAnchor(
        Rect.fromLTWH(.1, .2, .2, .3),
        Size(400, 800),
        .1,
      );
      expect(
        pulseFaceOnVideo(a, const Size(800, 800)),
        const Rect.fromLTWH(240, 160, 80, 240),
      );
      final mirror = pulseFaceOnVideo(a, const Size(800, 800), mirror: true);
      expect(mirror.left, closeTo(480, .001));
      expect(mirror.top, 160);
    },
  );
  test('Explicit back-camera metadata wins over the initial front default', () {
    expect(
      pulseCrownMirrored(
        local: true,
        facingMode: 'environment',
        frontCamera: true,
      ),
      false,
    );
    expect(
      pulseCrownMirrored(local: true, facingMode: 'user', frontCamera: false),
      true,
    );
    expect(
      pulseCrownMirrored(local: false, facingMode: 'user', frontCamera: true),
      false,
    );
    expect(
      pulseCrownMirrored(local: true, facingMode: null, frontCamera: true),
      true,
    );
  });
  testWidgets(
    'Crown tracks a face, hides on loss and stops sampling on expiry',
    (tester) async {
      var count = 0;
      PulseFaceAnchor? next = const PulseFaceAnchor(
        Rect.fromLTWH(.2, .2, .3, .3),
        Size(400, 800),
        .1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 600,
            child: PulseHeadCrown(
              until: DateTime.now().add(const Duration(seconds: 2)),
              sample: () async {
                count++;
                return next;
              },
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PulseGiftModel), findsOneWidget);
      next = null;
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(PulseGiftModel), findsNothing);
      next = const PulseFaceAnchor(
        Rect.fromLTWH(.4, .3, .2, .3),
        Size(400, 800),
        -.1,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(PulseGiftModel), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(PulseGiftModel), findsNothing);
      final stopped = count;
      await tester.pump(const Duration(seconds: 1));
      expect(count, stopped);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
