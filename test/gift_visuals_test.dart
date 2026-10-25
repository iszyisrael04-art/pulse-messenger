import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/gift_visuals.dart';
import 'package:pulse_messenger/gifter_ranks.dart';

void main() {
  testWidgets(
    'all sixteen gifts have real depth meshes and render at multiple angles',
    (tester) async {
      for (final sku in [
        'rose',
        'heart',
        'coffee',
        'star',
        'fire',
        'crown',
        'diamond',
        'rocket',
        'galaxy',
        'lion',
        'saturn',
        'trophy',
        'butterfly',
        'castle',
        'fireworks',
        'pearl',
      ]) {
        final mesh = GiftMesh.forSku(sku);
        expect(mesh.faces.length, greaterThan(20), reason: sku);
        final zs = mesh.faces.expand((f) => [f.a.z, f.b.z, f.c.z]);
        expect(
          zs.any((z) => z > 0) && zs.any((z) => z < 0),
          isTrue,
          reason: '$sku must have 3D depth',
        );
        for (final phase in [0.0, .4]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: PulseGiftModel(sku: sku, phase: phase),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: sku);
        }
      }
    },
  );
  testWidgets('rank badges label ten distinct ranks and hide rank zero', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PulseRankBadge(rank: 0)));
    expect(
      find.descendant(
        of: find.byType(PulseRankBadge),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    for (var rank = 1; rank <= 10; rank++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: PulseRankBadge(rank: rank, size: 100, label: true),
          ),
        ),
      );
      expect(find.text(pulseGifterNames[rank]), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
