import '../lib/chat_state.dart';
import '../lib/premium_result.dart';

void require(bool result, String reason) {
  if (!result) throw StateError(reason);
}

void main() {
  final message = <String, dynamic>{'id': 'one'};
  require(
    pulseReceipt({...message, 'pending': true}, [], 'me') ==
        PulseReceipt.queued,
    'Queued mark',
  );
  require(
    pulseReceipt(
          {...message, 'pending': true, 'failure': 'rejected'},
          [],
          'me',
        ) ==
        PulseReceipt.failed,
    'Failed mark',
  );
  require(
    pulseReceipt(message, [
          {'message_id': 'one', 'user_id': 'me', 'read_at': 'now'},
        ], 'me') ==
        PulseReceipt.sent,
    'Own read receipt must not mark outgoing read',
  );
  require(
    pulseReceipt(message, [
          {'message_id': 'one', 'user_id': 'friend', 'delivered_at': 'now'},
        ], 'me') ==
        PulseReceipt.delivered,
    'Delivered mark',
  );
  require(
    pulseReceipt(message, [
          {'message_id': 'one', 'user_id': 'friend', 'read_at': 'now'},
        ], 'me') ==
        PulseReceipt.read,
    'Read mark',
  );
  for (final own in [true, false]) {
    for (final read in [true, false]) {
      for (final visible in [true, false]) {
        require(
          pulseShouldNotify(own: own, read: read, visible: visible) ==
              (!own && !read && !visible),
          'Notification truth table',
        );
      }
    }
  }
  require(
    !pulseShouldNotify(own: false, read: false, visible: false, deleted: true),
    'Deleted notification',
  );
  final reactions = pulseReactionCounts([
    {'emoji': '❤️'},
    {'emoji': '❤️'},
    {'emoji': '👍'},
  ]);
  require(reactions['❤️'] == 2 && reactions['👍'] == 1, 'Reaction grouping');
  final redeemed = PulsePremiumResult.parse({
    'expires_at': '2030-01-10T00:00:00Z',
    'already_redeemed': false,
  });
  require(
    !redeemed.alreadyRedeemed && redeemed.message.contains('activated'),
    'First redemption',
  );
  final retry = PulsePremiumResult.parse(
    '{"expires_at":"2030-01-10T00:00:00Z","already_redeemed":true}',
  );
  require(
    retry.alreadyRedeemed && retry.expiresAt == redeemed.expiresAt,
    'Retry response',
  );
  require(
    pulsePremiumError(
      'PGRST202',
      'missing function',
    ).contains('needs an update'),
    'No raw schema code',
  );
  require(
    pulsePremiumError('P0001', 'Code unavailable').contains('invalid'),
    'Invalid-code message',
  );
  require(
    pulsePremiumError(
      'P0001',
      'This account already used this one-time code. Its Premium period has ended',
    ).contains('already used'),
    'Expired one-time redemption',
  );
  try {
    PulsePremiumResult.parse({'expires_at': 'not a date'});
    throw StateError('Malformed response accepted');
  } on FormatException {
    /* Expected. */
  }
  print(
    'PASS: receipt states, notification truth table, reaction counts, redemption response parsing and readable error mapping',
  );
}
