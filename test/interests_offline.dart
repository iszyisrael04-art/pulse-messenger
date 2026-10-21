import '../lib/interests.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void main() {
  check(
    pulseInterests(['gaming', 'gaming', 'invalid', 3]).join() == 'gaming',
    'sanitize and deduplicate interests',
  );
  final ranked = pulseRankForYou(
    [
      {'id': 'a', 'author_id': 'one', 'body': '#gaming highlights'},
      {'id': 'b', 'author_id': 'one', 'body': '#gaming clips'},
      {'id': 'c', 'author_id': 'two', 'body': '#football'},
      {'id': 'a', 'author_id': 'one', 'body': '#gaming highlights'},
    ],
    ['gaming'],
    7,
  );
  check(ranked.length == 3, 'deduplicate page boundaries');
  check(
    ranked.first['body'].toString().contains('gaming'),
    'prioritize selected topics',
  );
  check(
    ranked[1]['author_id'] != ranked.first['author_id'],
    'creator diversity',
  );
  check(
    ranked.map((r) => r['id']).toSet().length == 3,
    'retain every paginated candidate',
  );
  check(pulseRankForYou([], [], 0).isEmpty, 'empty account discovery');
  print(
    'PASS: interest validation, ranking, deduplication and creator diversity',
  );
}
