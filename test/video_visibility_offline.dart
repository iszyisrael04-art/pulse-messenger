import '../lib/video_visibility.dart';

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

void main() {
  require(pulseVideoVisible(100, 340, 800), 'Visible video rejected');
  require(!pulseVideoVisible(-200, 340, 800), 'Scrolled-away video autoplayed');
  require(
    !pulseVideoVisible(650, 340, 800),
    'Bottom navigation overlap autoplayed',
  );
  require(!pulseVideoVisible(80, 0, 800), 'Unlaid-out video autoplayed');
  require(
    !pulseVideoVisible(double.nan, 340, 800),
    'Invalid coordinates accepted',
  );
  require(!pulseVideoVisible(0, 340, 100), 'Collapsed viewport autoplayed');
  require(
    pulseVideoVisible(90, 200, 420),
    'Compact window stopped fully visible video',
  );
  print(
    'PASS: visibility thresholds, scroll-out, nav insets, invalid layout and compact viewport',
  );
}
