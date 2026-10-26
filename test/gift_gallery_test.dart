import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/gift_gallery.dart';
import 'package:pulse_messenger/live_ui.dart';
import 'package:pulse_messenger/pulse_coin.dart';

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
              people: const [
                {'user_id': 'host', 'display_name': 'A livestream creator'},
              ],
              recipient: 'host',
              test: false,
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
  testWidgets('Gift gallery visual QA uses bundled artwork', (tester) async {
    if (!Platform.isLinux) return;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk != null) {
        final file = File(
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        if (await file.exists()) {
          await (FontLoader('PulseGiftQA')..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes())),
              ))
              .load();
        }
      }
      final icons = File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            ))
            .load();
      }
    });
    final key = GlobalKey();
    const demo = <Map>[
      {
        'sku': 'galaxy',
        'title': 'Pulse Universe',
        'coins': 2500,
        'p_coins': 1000,
      },
      {'sku': 'lion', 'title': 'Lion', 'coins': 5000, 'p_coins': 2000},
      {
        'sku': 'dream',
        'title': 'Pulse Dream',
        'coins': 25999,
        'p_coins': 1299.95,
      },
      {
        'sku': 'phoenix',
        'title': 'Solar Phoenix',
        'coins': 25999,
        'p_coins': 1299.95,
      },
      {
        'sku': 'dragon',
        'title': 'Dragon Flame',
        'coins': 26999,
        'p_coins': 1349.95,
      },
      {
        'sku': 'sports_car',
        'title': 'Golden Sports Car',
        'coins': 29999,
        'p_coins': 1499.95,
      },
      {
        'sku': 'gorilla',
        'title': 'Jungle Silverback',
        'coins': 30000,
        'p_coins': 1500,
      },
      {
        'sku': 'royal_lions',
        'title': 'Royal Lions',
        'coins': 34000,
        'p_coins': 1700,
      },
      {
        'sku': 'pulse_stars',
        'title': 'Pulse Stars',
        'coins': 39999,
        'p_coins': 1999.95,
      },
      {
        'sku': 'thunder_falcon',
        'title': 'Thunder Falcon',
        'coins': 39999,
        'p_coins': 1999.95,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xff10151c),
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'PulseGiftQA',
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff81d5c2),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              key: key,
              child: PulseGiftGallery(
                gifts: demo,
                people: const [
                  {'user_id': 'demo', 'display_name': 'LIVE creator'},
                ],
                recipient: 'demo',
                test: false,
                balance: 2000000,
                onChoose: (_) {},
                onPreview: (_) {},
                onRecharge: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final g in demo) {
        await precacheImage(
          AssetImage('assets/gifts/thumb_${g['sku']}.png'),
          key.currentContext!,
        );
      }
    });
    await tester.tap(find.text('Cinema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulse Universe'));
    await tester.pumpAndSettle();
    final data = await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    });
    final b64 = base64Encode(data!);
    for (var i = 0; i < b64.length; i += 8000) {
      print(
        'PULSE_GIFT_GALLERY:${i ~/ 8000}:${b64.substring(i, (i + 8000).clamp(0, b64.length))}',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
