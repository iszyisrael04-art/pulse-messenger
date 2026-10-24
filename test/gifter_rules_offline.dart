import '../lib/gifter_rules.dart';

void main() {
  if (pulseGifterRank(0) != 0) throw StateError('Zero spend must be unranked');
  for (var i = 0; i < pulseGifterThresholds.length; i++) {
    final t = pulseGifterThresholds[i];
    if (pulseGifterRank(t) != i + 1 || pulseGifterRank(t - 1) != i)
      throw StateError('Rank boundary $i');
  }
  if (pulseGifterRank(10000000) != 10)
    throw StateError('Highest rank is capped at 10');
  print('PASS all ten gifter rank boundaries and 1m coin cap');
}
