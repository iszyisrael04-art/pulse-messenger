import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/profile_hero.dart';

void main() {
  for (final width in [320.0, 430.0, 1000.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'Profile video contains portrait and counts at $width / $textScale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1100));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var edited = false;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1100),
                  textScaler: TextScaler.linear(textScale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: PulseProfileHero(
                      background: const ColoredBox(
                        key: ValueKey('video-background'),
                        color: Colors.blue,
                      ),
                      avatar: const SizedBox.square(
                        dimension: 112,
                        child: Icon(Icons.person),
                      ),
                      displayName:
                          'An unusually long creator name for a small screen',
                      username: 'pulse_creator',
                      following: 234,
                      followers: 208,
                      likes: 1300,
                      verified: true,
                      signal: 'Making something new today',
                      onEdit: () => edited = true,
                      actions: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final banner = tester.getRect(
            find.byKey(const ValueKey('video-background')),
          );
          final portrait = tester.getRect(
            find.byKey(const ValueKey('profile-hero-portrait')),
          );
          expect(banner.contains(portrait.topLeft), isTrue);
          expect(banner.contains(portrait.bottomRight), isTrue);
          expect(find.text('Following'), findsOneWidget);
          expect(find.text('1.3K'), findsOneWidget);
          expect(
            tester
                .getRect(find.byKey(const ValueKey('profile-hero-counts')))
                .bottom,
            lessThanOrEqualTo(banner.bottom),
          );
          await tester.tap(find.byTooltip('Edit profile'));
          expect(edited, isTrue);
        },
      );
    }
  }
}
