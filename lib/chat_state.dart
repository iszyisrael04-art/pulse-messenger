enum PulseReceipt { queued, failed, sent, delivered, read }

PulseReceipt pulseReceipt(
  Map<String, dynamic> message,
  List<Map<String, dynamic>> receipts,
  String owner,
) {
  if (message['pending'] == true)
    return message['failure'] == null
        ? PulseReceipt.queued
        : PulseReceipt.failed;
  final others = receipts.where(
    (r) => r['message_id'] == message['id'] && r['user_id'] != owner,
  );
  if (others.any((r) => r['read_at'] != null)) return PulseReceipt.read;
  if (others.any((r) => r['delivered_at'] != null))
    return PulseReceipt.delivered;
  return PulseReceipt.sent;
}

bool pulseShouldNotify({
  required bool own,
  required bool read,
  required bool visible,
  bool deleted = false,
}) => !own && !read && !visible && !deleted;

Map<String, int> pulseReactionCounts(Iterable<dynamic> reactions) {
  final counts = <String, int>{};
  for (final r in reactions) {
    final emoji = r['emoji'] as String;
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  return counts;
}
