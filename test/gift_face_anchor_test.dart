import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_face_anchor.dart';
import '../lib/gift_visuals.dart';

void main() {
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
