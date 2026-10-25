import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/live_ui.dart';

void main() {
  test('Viewer count includes viewers and guests once, and excludes host', () {
    expect(pulseLiveViewerCount(['host', 'a', 'b'], 'a', 'host'), 2);
    expect(pulseLiveViewerCount(['a', 'b'], 'host', 'host'), 2);
    expect(pulseLiveViewerCount([], null, 'host'), 0);
  });
  testWidgets(
    'Menu shows pending seat badge and chat opens a clickable profile',
    (tester) async {
      var opened = false, menu = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PulseLiveMenuButton(requests: 3, onPressed: () => menu = true),
                PulseLiveComment(
                  avatar: const Icon(Icons.person),
                  name: 'Viewer',
                  message: 'Hello host',
                  openProfile: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byTooltip('LIVE menu · 3 seat requests'));
      expect(menu, true);
      await tester.tap(find.textContaining('Hello host'));
      expect(opened, true);
      expect(tester.takeException(), isNull);
    },
  );
}
