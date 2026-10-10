// Runs with plain Dart and no dependencies or network access.
import '../lib/validation.dart';

void main() {
  void check(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  for (final username in ['agent_fury', 'abc', 'pulse123']) {
    check(validateUsername(username) == null, 'Valid username rejected');
  }
  for (final username in ['', 'ab', '1pulse', 'has space', 'UPPER', 'a' * 25]) {
    check(validateUsername(username) != null, 'Invalid username accepted');
  }
  check(validatePassword('short') != null, 'Short password accepted');
  check(
    validatePassword('a secure password') == null,
    'Valid password rejected',
  );
  print('PASS: username boundaries and password minimum');
}
