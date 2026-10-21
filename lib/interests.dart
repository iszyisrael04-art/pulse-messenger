const pulseInterestTopics = <String, String>{
  'gaming': 'Gaming',
  'football': 'Football',
  'comedy': 'Comedy',
  'music': 'Music',
  'dance': 'Dance',
  'anime': 'Anime',
  'movies': 'Movies',
  'technology': 'Technology',
  'education': 'Learning',
  'art': 'Art',
  'fashion': 'Fashion',
  'food': 'Food',
  'fitness': 'Fitness',
  'travel': 'Travel',
  'business': 'Business',
  'nature': 'Nature',
};

List<String> pulseInterests(Object? value) => value is List
    ? value
          .whereType<String>()
          .where(pulseInterestTopics.containsKey)
          .toSet()
          .take(8)
          .toList()
    : [];

/// Ranks only content already authorized by the server; this grants no access.
List<Map<String, dynamic>> pulseRankForYou(
  Iterable<Map<String, dynamic>> posts,
  List<String> interests,
  int seed,
) {
  final seen = <Object?>{};
  final rows = posts.where((p) => seen.add(p['id'])).toList();
  int score(Map<String, dynamic> p) {
    final words = (p['body'] ?? '')
        .toString()
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_]+'))
        .toSet();
    return interests.where(words.contains).length * 100;
  }

  int jitter(Map<String, dynamic> p) => p['id'].toString().codeUnits.fold(
    seed,
    (a, b) => (a * 31 + b) & 0x7fffffff,
  );
  rows.sort((a, b) {
    final match = score(b).compareTo(score(a));
    return match != 0 ? match : jitter(a).compareTo(jitter(b));
  });
  // Keep all paginated candidates, while avoiding back-to-back creators when possible.
  final result = <Map<String, dynamic>>[];
  while (rows.isNotEmpty) {
    final next = result.isEmpty
        ? 0
        : rows.indexWhere((p) => p['author_id'] != result.last['author_id']);
    result.add(rows.removeAt(next < 0 ? 0 : next));
  }
  return result;
}
