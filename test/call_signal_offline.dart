import '../lib/call_signal.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24);
  final call = <String, dynamic>{
    'status': 'ringing',
    'ring_deadline': now.add(const Duration(seconds: 45)).toIso8601String(),
    'members': [
      {'user_id': 'caller', 'state': 'joined'},
      {'user_id': 'peer', 'state': 'ringing', 'received_at': null},
    ],
  };
  void check(bool value, String name) {
    if (!value) throw StateError(name);
  }

  check(
    pulseCallSignal(call, 'caller', now) == 'Calling…',
    'Unacknowledged device stays Calling',
  );
  (call['members'] as List)[1]['received_at'] = now.toIso8601String();
  check(
    pulseCallSignal(call, 'caller', now) == 'Ringing…',
    'Recipient acknowledgement starts Ringing',
  );
  check(
    pulseCallSignal(call, 'caller', now.add(const Duration(seconds: 46))) ==
        'No answer',
    'Expired calls do not ring',
  );
  call['status'] = 'active';
  check(pulseCallSignal(call, 'caller', now) == 'Connected', 'Accepted call');
  call['status'] = 'ended';
  check(pulseCallSignal(call, 'caller', now) == 'Call ended', 'Ended call');
  print('PASS call delivery, ringing, answer and expiry states');
}
