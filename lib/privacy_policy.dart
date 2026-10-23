import 'package:flutter/material.dart';
import 'profile_rules.dart';

const pulsePrivacyText =
    '''PULSE private beta — Privacy Policy
Version $pulsePrivacyVersion

What Pulse stores
We store the email address or phone number used for your account, your profile, messages, media, posts, reactions, follows, social activity alerts and their read state/preferences, active-status settings, device presence heartbeats and last-seen timestamps, reports, device notification registrations, animated-profile entitlements, boost purchases and historical redemption records. Community membership/join requests, staff moderation records and appeals are also stored in upgraded deployments. If you choose to appeal with a video, authorized staff review it manually; with your explicit consent, a time-limited video link may be emailed to pulseservicemanagement@gmail.com. The video is not used for automated identity or face recognition in this version. When you create an account in this version, we record the policy version you accepted and the server time. Passwords are handled by Supabase Auth; Pulse does not store readable passwords.

Who can see your information
Your profile name, username, picture, bio and optional Profile Signal are visible to signed-in users, subject to blocking. A private account restricts followers and content; it does not hide all profile details. Post audience controls determine who can view a post. Chat access is restricted to conversation members. Pocket notes and quick replies are available only to their owner through the app.

Messages and security
Connections use encryption in transit and backend access rules restrict access. Messages and Pocket notes are NOT end-to-end encrypted. The service operator and authorized infrastructure administrators may access stored data for operation, support or abuse handling. Do not send highly sensitive information during this beta.

Service providers and permissions
Supabase hosts account, database and media services. Configured email/SMS providers deliver verification codes. Firebase may process device registration and notification data when enabled. Calling may use a configured LiveKit service; availability depends on deployment. These providers may process data outside your country. Camera, microphone, files and notification access are requested for features you choose to use. Pulse does not upload your phone address book in this version.

Your choices
You can edit your profile, select post audiences, block accounts, report abuse and turn off notifications. Signing out removes the local session; it does not delete your account. Delete-for-me hides a message for you; deletion elsewhere does not remove copies another person already downloaded or saved. The existing account export covers selected data, not every record.

Retention and requests
Data is retained to provide the service until removed through available controls or by the operator. Backups, security records and reports may be retained beyond a visible deletion. This beta does not yet offer complete self-service account deletion. For help or an account access or deletion request, email pulseservicemanagement@gmail.com. You can open a support draft from Settings → Help & support.

Beta limitations and changes
Do not submit payment card details: checkout is not connected. Animated profiles are a standalone purchase and boost plans promote videos to real viewers. Redemption codes have been retired. This beta policy describes the current implementation. The operator identity, complete retention schedule and country-specific review must be completed before public launch. A changed policy will be given a new version; this checkbox does not authorize unrelated future uses of your data.
''';

class PulsePrivacyPage extends StatelessWidget {
  const PulsePrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy Policy')),
    body: SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: const [Text(pulsePrivacyText, style: TextStyle(height: 1.6))],
      ),
    ),
  );
}

class PulsePrivacyAgreement extends StatelessWidget {
  const PulsePrivacyAgreement({
    super.key,
    required this.accepted,
    required this.onChanged,
    this.error,
  });
  final bool accepted;
  final ValueChanged<bool>? onChanged;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: accepted,
        onChanged: onChanged == null ? null : (v) => onChanged!(v == true),
        title: const Text('I agree to the Privacy Policy'),
        subtitle: const Text('Required to create a Pulse account.'),
      ),
      TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PulsePrivacyPage()),
        ),
        child: const Text('Read Privacy Policy'),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
