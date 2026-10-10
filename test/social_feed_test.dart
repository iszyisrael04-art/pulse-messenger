import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulse_messenger/repository.dart';
import 'package:pulse_messenger/social_repository.dart';

class FakeSocialStore extends SocialStore {
  FakeSocialStore()
    : super(
        PulseRepository(
          SupabaseClient('https://example.supabase.co', 'test-only'),
        ),
      );
  final requests = <Completer<List<SocialRow>>>[];
  final cursors = <SocialRow?>[];
  @override
  String get uid => 'me';
  @override
  Future<List<SocialRow>> feed({
    String mode = 'discovery',
    String kind = 'all',
    String? author,
    SocialRow? cursor,
  }) {
    cursors.add(cursor);
    final request = Completer<List<SocialRow>>();
    requests.add(request);
    return request.future;
  }
}

SocialRow row(String id) => {
  'id': id,
  'created_at': '2026-10-10T00:00:00Z',
  'author_id': 'other',
  'follow_state': 'accepted',
};
void main() {
  late FakeSocialStore store;
  late SocialFeedController feed;
  setUp(() {
    store = FakeSocialStore();
    feed = SocialFeedController(store);
  });
  tearDown(() async {
    feed.dispose();
    await store.repo.db.dispose();
  });
  test('a delayed old page cannot overwrite a newer refresh', () async {
    final old = feed.load(reset: true);
    final latest = feed.load(reset: true);
    store.requests[1].complete([row('latest')]);
    await latest;
    store.requests[0].complete([row('stale')]);
    await old;
    expect(feed.rows.map((x) => x['id']), ['latest']);
    expect(feed.loading, false);
  });
  test(
    'pagination suppresses duplicates while retaining the server cursor',
    () async {
      final first = feed.load(reset: true);
      store.requests[0].complete(List.generate(12, (i) => row('p$i')));
      await first;
      final next = feed.load();
      expect(store.cursors[1]?['id'], 'p11');
      store.requests[1].complete([row('p11'), row('p12')]);
      await next;
      expect(feed.rows.length, 13);
      expect(feed.cursor?['id'], 'p12');
      expect(feed.hasMore, false);
    },
  );
  test(
    'failed filter refresh does not display rows from the previous feed',
    () async {
      final first = feed.load(reset: true);
      store.requests[0].complete([row('discovery')]);
      await first;
      feed.mode = 'following';
      final next = feed.load(reset: true);
      store.requests[1].completeError(SocialFailure('Offline'));
      await next;
      expect(feed.rows, isEmpty);
      expect(feed.error, 'Offline');
    },
  );
  test('unfollowing removes that creator from the following feed', () async {
    feed.mode = 'following';
    feed.rows = [row('one'), row('two')];
    feed.change({...row('one'), 'follow_state': 'none'}, 'one');
    expect(feed.rows, isEmpty);
  });
}
