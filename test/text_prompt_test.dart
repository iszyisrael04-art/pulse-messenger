import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/channels.dart' show channelPrompt;

void main() {
  testWidgets(
    'channel-style prompts survive keyboard, save and reverse animation',
    (tester) async {
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(await channelPrompt(context, 'Channel action'));
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      for (final text in ['new_admin', 'Announcement']) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.text('Save'));
        // Exercise both the result future and route's later unmount.
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(results, ['new_admin', 'Announcement']);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results.last, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
