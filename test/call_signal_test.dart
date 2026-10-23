import 'package:flutter_test/flutter_test.dart';
import 'call_signal_offline.dart' as checks;

void main() {
  test(
    'Calling only becomes Ringing after device acknowledgement',
    checks.main,
  );
}
