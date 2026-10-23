/// Seed the first page without replaying old notifications after every launch.
class PulseActivityAlerts {
  final _seen = <String>{};
  bool seeded = false;
  DateTime? startedAt;
  Map<String, int> collect(
    List<Map<String, dynamic>> items, {
    bool viewing = false,
    String? asOf,
  }) {
    final counts = <String, int>{};
    for (final item in items) {
      final id = item['id'] as String?;
      if (id == null || !_seen.add(id)) continue;
      final created = DateTime.tryParse(item['created_at']?.toString() ?? '');
      final recent =
          startedAt == null || created == null || !created.isBefore(startedAt!);
      if (seeded && recent && !viewing && item['read'] != true) {
        final kind = item['kind'] as String? ?? 'update';
        counts[kind] = (counts[kind] ?? 0) + 1;
      }
    }
    if (!seeded) startedAt = DateTime.tryParse(asOf ?? '');
    seeded = true;
    while (_seen.length > 1000) {
      _seen.remove(_seen.first);
    }
    return counts;
  }
}

String pulseActivityAlertBody(String kind, int count) {
  final feature = switch (kind) {
    'like' => count == 1 ? 'like' : 'likes',
    'comment' => count == 1 ? 'comment' : 'comments',
    'follow' => count == 1 ? 'follower' : 'followers',
    'follow_request' => count == 1 ? 'follow request' : 'follow requests',
    'mention_post' || 'mention_comment' => count == 1 ? 'mention' : 'mentions',
    'community_tag' => count == 1 ? 'community mention' : 'community mentions',
    'publish' =>
      count == 1
          ? 'post from someone you follow'
          : 'posts from people you follow',
    _ => count == 1 ? 'activity update' : 'activity updates',
  };
  return '$count new $feature';
}
