import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/gift_cinematic.dart';
import '../lib/repository.dart' hide Row;

class UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected network access');
}

void main() {
  testWidgets('Reduced motion uses a plain silent notice and gifts cannot block exit', (
    tester,
  ) async {
    final repo = PulseRepository(UnusedClient());
    var exited = false, completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: TextButton(
                    onPressed: () => exited = true,
                    child: const Text('Leave live'),
                  ),
                ),
                IgnorePointer(
                  child: PulseLiveGiftPresentation(
                    repo: repo,
                    event: const {
                      'sku': 'lion',
                      'display_name': 'Viewer',
                      'avatar_path': null,
                      'sender_id': null,
                      'quantity': 2,
                      'title': 'Lion',
                    },
                    onComplete: () => completed++,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Video), findsNothing);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    await tester.tap(find.text('Leave live'));
    expect(exited, true);
    await tester.pump(const Duration(seconds: 4));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    expect(tester.takeException(), isNull);
  });
}

