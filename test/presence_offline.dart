import '../lib/presence_rules.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 8);
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  final active = PulseActiveStatus.fromServer({
    'online': true,
    'expires_in': 70,
    'last_seen': now.toIso8601String(),
  }, now);
  check(
    active.online(now) && active.label(now) == 'Online now',
    'Online lease',
  );
  check(
    !active.online(now.add(const Duration(seconds: 70))),
    'Lease expires without fresh heartbeat',
  );
  final malicious = PulseActiveStatus.fromServer({
    'online': true,
    'expires_in': 999999,
  }, now);
  check(
    !malicious.online(now.add(const Duration(seconds: 71))),
    'No unbounded online claim',
  );
  check(
    !PulseActiveStatus.fromServer({
      'online': false,
      'expires_in': 70,
    }, now).online(now),
    'Offline response never green',
  );
  check(
    PulseActiveStatus.fromServer({}, now).label(now) == '',
    'Unknown/hidden status has no label',
  );
  check(
    PulseActiveStatus(
          now,
          now.subtract(const Duration(minutes: 5)),
        ).label(now) ==
        'Last seen 5m ago',
    'Last seen minutes',
  );
  check(
    PulseActiveStatus(now, now.subtract(const Duration(days: 1))).label(now) ==
        'Last seen yesterday',
    'Last seen yesterday',
  );
  print(
    'PASS: online lease expiry, invalid response bounds, hidden status and last seen labels',
  );
}
