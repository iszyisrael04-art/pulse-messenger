import '../lib/phone_rules.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void main() {
  check(
    pulsePhoneNumber('0803 123 4567', 'NG') == '+2348031234567',
    'Nigeria national trunk prefix',
  );
  check(
    pulsePhoneNumber('+44 7911 123456', 'NG') == '+447911123456',
    'explicit international country overrides selected country',
  );
  check(
    pulsePhoneNumber('(202) 555-0123', 'US') == '+12025550123',
    'US punctuation',
  );
  check(
    pulsePhoneNumber('06 2345 6789', 'IT') == '+390623456789',
    'Italy significant leading zero',
  );
  check(pulsePhoneNumber('123', 'NG') == null, 'reject short number');
  check(pulsePhoneNumber('', 'NG') == null, 'reject empty input');
  check(
    pulsePhoneError('phone_provider_disabled', '').contains('email'),
    'explain unavailable SMS without disabling OTP',
  );
  print('PASS: international formatting, country rules and SMS setup guidance');
}
