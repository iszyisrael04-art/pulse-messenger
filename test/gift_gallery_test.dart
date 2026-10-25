import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_gallery.dart';
import '../lib/live_ui.dart';
import '../lib/pulse_coin.dart';

void main() {
  const gifts = <Map>[
    {'sku': 'rose', 'title': 'Rose', 'coins': 10, 'p_coins': .5},
    {'sku': 'galaxy', 'title': 'Galaxy', 'coins': 2500, 'p_coins': 1000},
  ];
  testWidgets('Gift browsing and preview never submit a paid gift', (
    tester,
  ) async {
    var previews = 0;
    Map? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseGiftGallery(
            gifts: gifts,
            people: const [
              {'user_id': 'host', 'display_name': 'The host'},
            ],
            recipient: 'host',
            test: false,
            balance: 100,
            onChoose: (g) => selected = g,
            onPreview: (_) => previews++,
            onRecharge: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cinema'));
    await tester.pumpAndSettle();
    expect(find.text('Rose'), findsNothing);
    await tester.tap(find.text('Pulse Universe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    expect(previews, 1);
    expect(selected, isNull);
    await tester.tap(find.text('Continue'));
    expect(selected?['sku'], 'galaxy');
    expect(selected?['recipient'], 'host');
    expect(selected?['title'], 'Pulse Universe');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Tiny currency art and compact LIVE header retain usable controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var followed = 0, left = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PulseLiveHeader(
                  avatar: const CircleAvatar(radius: 17),
                  name: 'A long livestream creator name',
                  viewers: 200,
                  openProfile: () {},
                  leave: () => left++,
                  follow: () => followed++,
                ),
                const PulseCoin(),
              ],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PulseCoin)), const Size(12, 12));
      await tester.tap(find.text('+ Follow'));
      await tester.tap(find.byTooltip('Leave live'));
      expect(followed, 1);
      expect(left, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Gift tray works on a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: PulseGiftGallery(
              gifts: gifts,
              people: const [],
              recipient: 'host',
              test: true,
              onChoose: (_) {},
              onPreview: (_) {},
              onRecharge: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
  });
}
