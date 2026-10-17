String pulseActivityAction(String kind, {bool video = false}) => switch (kind) {
  'community_tag' => 'tagged one of your communities',
  'follow' => 'started following you',
  'follow_request' => 'requested to follow you',
  'like' => video ? 'liked your video' : 'liked your post',
  'comment' => video ? 'commented on your video' : 'commented on your post',
  'mention_post' => video ? 'tagged you in a video' : 'tagged you in a post',
  'mention_comment' => 'mentioned you in a comment',
  'publish' => video ? 'shared a new video' : 'shared a new post',
  _ => 'shared an update',
};

String pulseActivityTime(String? value, DateTime now) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  final elapsed = now.difference(date);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${date.day}/${date.month}/${date.year}';
}
