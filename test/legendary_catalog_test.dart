import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/legendary_catalog.dart';
import '../lib/legendary_overlay.dart';
import '../lib/gift_cinematic.dart';
import '../lib/repository.dart' hide Row;

class LegendaryOfflineClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('Network not allowed');
}

void main() {
  test(
    'Nine legendary gifts have fixed IDs, prices and full original durations',
    () {
      expect(pulseLegendaryGifts.values.map((g) => g.coins).toList(), [
        1000,
        5000,
        7500,
        10000,
        15000,
        20000,
        30000,
        50000,
        60000,
      ]);
      expect(pulsePremiumGifts.values.map((g) => g.coins).toList(), [30000, 35000, 40000, 45000]);
      expect(pulseCinematicGifts.length, 13);
      expect(pulseLegendaryForEvent({'sku': 'premium_white_tiger', 'coins': 35000})?.title, 'White Tiger');
      for (final g in pulseLegendaryGifts.values) {
        expect(g.durationMs, inInclusiveRange(5042, 5167));
      }
      expect(
        pulseLegendaryForEvent({'sku': 'legend_lion_king', 'coins': 299}),
        isNull,
      );
      expect(
        pulseLegendaryForEvent({'sku': 'legend_lion_king', 'coins': 1000})
            ?.title,
        'Lion King',
      );
      expect(
        pulseLegendaryForEvent({
          'sku': 'https://evil.test/anything',
          'coins': 1000,
        }),
        isNull,
      );
    },
  );
  testWidgets(
    'Under-300 gift events cannot instantiate legendary playback or audio',
    (tester) async {
      final repo = PulseRepository(LegendaryOfflineClient());
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulseLiveGiftPresentation(
              repo: repo,
              event: const {
                'sku': 'legend_lion_king',
                'coins': 299,
                'display_name': 'Viewer',
                'quantity': 1,
                'title': 'Lion King',
              },
              onComplete: () => completed++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PulseLegendaryOverlay), findsNothing);
      expect(find.byType(Video), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(completed, 1);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
