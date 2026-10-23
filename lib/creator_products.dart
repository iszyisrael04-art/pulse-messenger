/// Server catalog is authoritative; integer cents avoid floating-point prices.
String pulseUsd(int cents) => cents % 100 == 0
    ? '\$${cents ~/ 100}'
    : '\$${(cents / 100).toStringAsFixed(2)}';

String pulseViewCap(int count) =>
    count >= 1000 && count % 1000 == 0 ? '${count ~/ 1000}K' : '$count';

String pulseProductPeriod(String period) => switch (period) {
  'once' => 'one-time unlock',
  'month' => 'per month',
  'year' => 'per year',
  _ => throw const FormatException('Unknown billing period'),
};
