import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/validation.dart';

void main() {
  test(
    'username rejects spaces, uppercase, numbers first and length violations',
    () {
      for (final value in [
        '',
        'ab',
        '1pulse',
        'has space',
        'UPPER',
        'a' * 25,
      ]) {
        expect(validateUsername(value), isNotNull);
      }
      for (final value in ['agent_fury', 'abc', 'pulse123']) {
        expect(validateUsername(value), isNull);
      }
    },
  );
  test('password registration requires twelve characters', () {
    expect(validatePassword('short'), isNotNull);
    expect(validatePassword('longer password'), isNull);
  });
}
