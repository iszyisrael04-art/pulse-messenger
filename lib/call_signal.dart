/// Ringing means a recipient device acknowledged delivery, never just presence.
String pulseCallSignal(Map call, String viewer, DateTime now) {
  if (call['status'] == 'ended') return 'Call ended';
  if (call['status'] == 'active') return 'Connected';
  final deadline = DateTime.tryParse('${call['ring_deadline']}');
  if (deadline != null && !deadline.isAfter(now.toUtc())) return 'No answer';
  final members =
      call['members'] as List? ?? call['pulse_call_members'] as List? ?? [];
  final received = members.any(
    (m) =>
        m['user_id'] != viewer &&
        m['state'] == 'ringing' &&
        m['received_at'] != null,
  );
  return received ? 'Ringing…' : 'Calling…';
}
