import '../lib/support_draft.dart';

void main() {
  final uri = supportEmailDraft(
    category: 'Account & login',
    subject: 'Hello + Pulse\r\nCc: nobody',
    details: 'OTP & login + issue 😭\nSecond line',
    platform: 'Android',
  );
  if (uri.scheme != 'mailto' || uri.path != pulseSupportEmail)
    throw StateError('Wrong recipient');
  if (uri.queryParameters['subject']!.contains('\n') ||
      uri.queryParameters.length != 2)
    throw StateError('Invalid headers');
  if (!uri.queryParameters['body']!.startsWith(
    'OTP & login + issue 😭\nSecond line',
  ))
    throw StateError('Body encoding lost content');
  if (!uri.queryParameters['body']!.contains(pulseSupportVersion))
    throw StateError('Version missing');
  print(
    'PASS: fixed support recipient, safe subject and Unicode draft encoding.',
  );
}
