import '../lib/profile_rules.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main() {
  check(
    needsPrivacyAgreement(register: true, reset: false, codeSent: false),
    'Registration needs consent',
  );
  check(
    !needsPrivacyAgreement(register: false, reset: false, codeSent: false),
    'Login must not ask',
  );
  check(
    !needsPrivacyAgreement(register: true, reset: false, codeSent: true),
    'OTP must not ask twice',
  );
  check(
    !needsPrivacyAgreement(register: true, reset: true, codeSent: false),
    'Recovery must not ask',
  );
  final now = DateTime.utc(2026, 10, 17);
  final exits = PulseExitPresses();
  check(!exits.press(now), 'First Back must not exit');
  check(
    exits.press(now.add(const Duration(milliseconds: 1800))),
    'Second Back exits',
  );
  check(!exits.press(now.add(const Duration(seconds: 4))), 'Pair must reset');
  check(
    !exits.press(now.add(const Duration(seconds: 7))),
    'Expired press must not exit',
  );
  exits.reset();
  check(
    !exits.press(now.add(const Duration(seconds: 8))),
    'Backgrounding resets',
  );
  check(
    profileMotionAllowed(now.add(const Duration(days: 1)), now),
    'Premium motion',
  );
  check(!profileMotionAllowed(now, now), 'Exact expiry disables');
  check(!profileMotionAllowed(null, now), 'Free static');
  check(
    !profileMotionAllowed(
      now.add(const Duration(days: 1)),
      now,
      reducedMotion: true,
    ),
    'Reduced motion',
  );
  check(
    !profileMotionAllowed(
      now.add(const Duration(days: 1)),
      now,
      visible: false,
    ),
    'Hidden motion',
  );
  check(pulseProfileBackgrounds.length == 8, 'Eight backgrounds');
  print('Profile agreement, exit timing and motion checks passed.');
}
