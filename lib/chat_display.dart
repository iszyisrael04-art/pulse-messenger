String pulseChatPreview(Map? message, String owner, {String? senderName, bool showOwnLabel = true}) {
  if (message == null ||
      message['body'] == null && message['created_at'] == null)
    return 'Start the conversation';
  final body = (message['body'] ?? '')
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final kind = message['media_kind'];
  final label = kind == 'image'
      ? 'Photo'
      : kind == 'video'
      ? 'Video'
      : kind == 'audio'
      ? 'Voice message'
      : kind == 'file' || message['has_attachment'] == true
      ? 'Attachment'
      : message['status_reply'] == true
      ? 'Status reply'
      : '';
  return '${message['sender_id'] == owner
      ? (showOwnLabel ? 'You: ' : '')
      : senderName != null && senderName.trim().isNotEmpty
      ? '${senderName.trim()}: '
      : ''}${label.isEmpty ? '' : '$label${body.isEmpty ? '' : ' · '}'}$body';
}

String pulseChatTime(DateTime? time, DateTime now) {
  if (time == null) return '';
  final local = time.toLocal();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day)
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year.toString().padLeft(4, '0').substring(2)}';
}

String pulseChatDay(DateTime time, DateTime now) {
  final day = DateTime(time.year, time.month, time.day),
      today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (day == yesterday) return 'Yesterday';
  return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';
}

String? pulseChatDelivery(Map? message, String owner) {
  if (message == null || message['sender_id'] != owner || message['created_at'] == null) return null;
  final value = message['delivery'];
  return value == 'read' || value == 'delivered' ? value as String : 'sent';
}
