import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/gift_gallery.dart';

void main() {
  testWidgets(
    'Preview does not spend; tapping a gift sends exactly one to the selected recipient',
    (tester) async {
      int previews = 0;
      Map? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulseGiftGallery(
              gifts: const [
                {'sku': 'rose', 'title': 'Rose', 'coins': 10, 'p_coins': .5},
                {
                  'sku': 'lion',
                  'title': 'Lion',
                  'coins': 5000,
                  'p_coins': 2000,
                },
              ],
              people: const [
                {'user_id': 'host', 'display_name': 'Host'},
              ],
              recipient: 'host',
              test: false,
              balance: 10000,
              onChoose: (g) => sent = g,
              onPreview: (_) => previews++,
              onRecharge: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(find.text('Rose'), findsNothing);
      await tester.tap(find.byTooltip('Preview Lion'));
      await tester.pump();
      expect(previews, 1);
      expect(sent, isNull);
      await tester.tap(find.text('Lion'));
      await tester.pump();
      expect(sent?['sku'], 'lion');
      expect(sent?['recipient'], 'host');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
