import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/repository.dart' hide Row;
import '../lib/social_repository.dart';
import '../lib/social_create.dart';

class OfflineComposerRepository implements PulseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository access: ${invocation.memberName}',
  );
}

class ComposerStore extends SocialStore {
  ComposerStore() : super(OfflineComposerRepository());
  Map<String, dynamic>? published;
  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> values) async {
    if (name != 'write_options') throw StateError('Unexpected RPC $name');
    published = Map<String, dynamic>.from(values);
    return values['p_id'];
  }
}

void main() {
  for (final width in [360.0, 1100.0]) {
    testWidgets('media-first composer fits width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = ComposerStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: SocialComposer(store: store),
        ),
      );
      expect(find.text('Make it a moment.'), findsOneWidget);
      expect(find.text('Post now'), findsOneWidget);
      expect(find.text('Choose media'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
  }
  testWidgets(
    'caption, audience and video-download choice are saved with the draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = ComposerStore();
      await tester.pumpWidget(MaterialApp(home: SocialComposer(store: store)));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'A moment worth sharing');
      await tester.ensureVisible(find.text('Who can watch'));
      await tester.tap(find.text('Who can watch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Only me'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Allow video downloads'));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();
      expect(store.published?['p_body'], 'A moment worth sharing');
      expect(store.published?['p_audience'], 'private');
      expect(store.published?['p_draft'], true);
      expect(store.published?['p_allow_download'], false);
      expect(store.published?['p_media'], isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
