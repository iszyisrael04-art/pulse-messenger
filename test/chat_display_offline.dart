import '../lib/chat_display.dart';

void check(bool value, String name) {
  if (!value) throw StateError(name);
}

void main() {
  check(
    pulseChatPreview(null, 'a') == 'Start the conversation',
    'Empty conversation',
  );
  check(
    pulseChatPreview({'body': null, 'created_at': null}, 'a') ==
        'Start the conversation',
    'No latest visible message',
  );
  check(
    pulseChatPreview({'body': '  Hello\nthere  ', 'sender_id': 'a'}, 'a') ==
        'You: Hello there',
    'Own normalized text',
  );
  check(
    pulseChatPreview({
          'body': 'caption',
          'media_kind': 'image',
          'sender_id': 'b',
        }, 'a') ==
        'Photo · caption',
    'Photo caption',
  );
  check(
    pulseChatPreview({
          'body': '',
          'media_kind': 'audio',
          'sender_id': 'b',
        }, 'a') ==
        'Voice message',
    'Voice preview',
  );
  check(
    pulseChatPreview({'body': '', 'has_attachment': true}, 'a') == 'Attachment',
    'Legacy file preview',
  );
  final now = DateTime(2026, 1, 1, 12);
  check(
    pulseChatDay(DateTime(2025, 12, 31, 23), now) == 'Yesterday',
    'Year boundary yesterday',
  );
  check(
    pulseChatDay(DateTime(2026, 1, 1, 1), now) == 'Today',
    'Same calendar day',
  );
  check(
    pulseChatDay(DateTime(2025, 12, 29), now) == '29/12/2025',
    'Older calendar day',
  );
  check(
    pulseChatTime(DateTime(2026, 1, 1, 3, 4), now) == '03:04',
    'Clock padding',
  );
  check(
    pulseChatTime(DateTime(2025, 12, 31), now) == '31/12/25',
    'Date preview',
  );
  print(
    'PASS: text/media previews, sender labels, calendar boundaries and clocks',
  );
}
