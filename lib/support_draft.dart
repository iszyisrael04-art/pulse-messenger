const pulseSupportEmail = 'pulseservicemanagement@gmail.com';
const pulseSupportVersion = '0.1.0+34';

String supportSubject(String category, String subject) =>
    'Pulse support · $category — ${subject.trim()}'.replaceAll(
      RegExp(r'[\r\n]+'),
      ' ',
    );

String supportBody(
  String details,
  String platform, {
  String? displayName,
  String? username,
  String? accountEmail,
}) =>
    '${details.trim()}\n\n---\nPulse $pulseSupportVersion · $platform'
    '${displayName == null ? '' : '\nPulse account name: ${displayName.replaceAll(RegExp(r"[\r\n]+"), " ")}'}'
    '${username == null ? '' : '\nPulse username: @$username'}'
    '\nAccount email: ${accountEmail == null || accountEmail.isEmpty ? 'No email linked (phone account)' : accountEmail}';

Uri supportEmailDraft({
  required String category,
  required String subject,
  required String details,
  required String platform,
  String? displayName,
  String? username,
  String? accountEmail,
}) {
  final fields = {
    'subject': supportSubject(category, subject),
    'body': supportBody(
      details,
      platform,
      displayName: displayName,
      username: username,
      accountEmail: accountEmail,
    ),
  };
  // Non-HTTP URI fields need component encoding; literal + and & stay intact.
  final query = fields.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');
  return Uri(scheme: 'mailto', path: pulseSupportEmail, query: query);
}
