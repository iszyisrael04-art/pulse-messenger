import '../lib/creator_products.dart';

void main() {
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  check(pulseUsd(100) == r'$1', 'Motion price');
  check(pulseUsd(2500) == r'$25' && pulseUsd(4000) == r'$40', 'Monthly prices');
  check(pulseUsd(100000) == r'$1000', 'Annual price');
  check(
    pulseViewCap(50000) == '50K' &&
        pulseViewCap(100000) == '100K' &&
        pulseViewCap(500000) == '500K',
    'View caps',
  );
  check(
    pulseProductPeriod('once') == 'one-time unlock',
    'No invented subscription for motion',
  );
  check(
    pulseProductPeriod('month') == 'per month' &&
        pulseProductPeriod('year') == 'per year',
    'Billing periods',
  );
  print('PASS: exact USD prices, standalone motion unlock and promotion caps');
}
