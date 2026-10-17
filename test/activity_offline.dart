import '../lib/activity_labels.dart';
import '../lib/support_draft.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 22);
  if (pulseActivityAction('mention_post', video: true) !=
      'tagged you in a video')
    throw StateError('Video mention');
  if (pulseActivityAction('publish', video: true) != 'shared a new video')
    throw StateError('Video post');
  if (pulseActivityTime(
        now.subtract(const Duration(minutes: 3)).toIso8601String(),
        now,
      ) !=
      '3m ago')
    throw StateError('Time label');
  if (pulseActivityTime('invalid', now) != '') throw StateError('Invalid date');
  final email = supportEmailDraft(
    category: 'Help',
    subject: 'Login',
    details: 'Cannot access account',
    platform: 'Windows',
    displayName: 'Pulse Creator',
    username: 'pulse_creator',
    accountEmail: 'creator@example.invalid',
  );
  final body = email.queryParameters['body']!;
  if (!body.contains('Pulse account name: Pulse Creator') ||
      !body.contains('@pulse_creator') ||
      !body.contains('creator@example.invalid'))
    throw StateError('Account identity missing');
  if (!supportBody(
    'Hello',
    'Android',
    displayName: 'Phone user',
  ).contains('No email linked'))
    throw StateError('Phone-only email invented');
  print('PASS: activity labels, timestamps and support identity.');
}
