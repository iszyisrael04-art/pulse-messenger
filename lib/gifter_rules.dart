const pulseGifterThresholds = [
  1,
  100,
  1000,
  5000,
  10000,
  25000,
  50000,
  100000,
  500000,
  1000000,
];
const pulseGifterNames = [
  'Unranked',
  'Spark',
  'Bronze',
  'Silver',
  'Gold',
  'Platinum',
  'Emerald',
  'Diamond',
  'Master',
  'Legend',
  'Sovereign',
];
int pulseGifterRank(int spent) {
  var rank = 0;
  for (final threshold in pulseGifterThresholds) {
    if (spent >= threshold) rank++;
  }
  return rank;
}
