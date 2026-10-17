import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'support_draft.dart';
import 'repository.dart' hide Row;

class PulseHelpPage extends StatefulWidget {
  const PulseHelpPage({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseHelpPage> createState() => _PulseHelpPageState();
}

class _PulseHelpPageState extends State<PulseHelpPage> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(), details = TextEditingController();
  String category = 'App issue';
  bool busy = false;
  String? notice;
  String? get accountName => widget.repo.me?['display_name'] as String?;
  String? get username => widget.repo.me?['username'] as String?;
  String? get accountEmail => widget.repo.db.auth.currentUser?.email;
  String get platform => Platform.isAndroid
      ? 'Android'
      : Platform.isWindows
      ? 'Windows'
      : Platform.operatingSystem;
  @override
  void dispose() {
    subject.dispose();
    details.dispose();
    super.dispose();
  }

  Future<void> email() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final opened = await launchUrl(
        supportEmailDraft(
          category: category,
          subject: subject.text,
          details: details.text,
          platform: platform,
          displayName: accountName,
          username: username,
          accountEmail: accountEmail,
        ),
        mode: LaunchMode.externalApplication,
      );
      if (mounted)
        setState(
          () => notice = opened
              ? 'Your email app was opened. Review the draft and send it there.'
              : 'No email app opened. Copy your message and email it to the address below.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => notice =
              'Could not open an email app. Copy your message and send it manually.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copy({bool addressOnly = false}) async {
    if (!addressOnly && !form.currentState!.validate()) return;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: addressOnly
              ? pulseSupportEmail
              : 'To: $pulseSupportEmail\nSubject: ${supportSubject(category, subject.text)}\n\n${supportBody(details.text, platform, displayName: accountName, username: username, accountEmail: accountEmail)}',
        ),
      );
      if (mounted)
        setState(
          () => notice = addressOnly
              ? 'Support address copied.'
              : 'Message copied. Paste it into your email app and send.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => notice =
              'Could not copy. You can select the support address below.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & support')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.support_agent_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'How can we help?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Describe what happened and what you expected. This opens a draft in your email app; send it there to contact Pulse support.',
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(accountName ?? 'Pulse account'),
                  subtitle: Text(
                    '@${username ?? 'choose_username'}\n${accountEmail?.isNotEmpty == true ? accountEmail : 'No email linked (phone account)'}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const SelectableText(pulseSupportEmail),
              TextButton.icon(
                onPressed: () => copy(addressOnly: true),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy email address'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Topic'),
                items: [
                  for (final c in [
                    'App issue',
                    'Account & login',
                    'Premium & codes',
                    'Safety & privacy',
                    'Feedback',
                  ])
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: busy ? null : (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: subject,
                enabled: !busy,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Subject'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a subject' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                enabled: !busy,
                minLines: 5,
                maxLines: 10,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Your message',
                  hintText: 'What were you doing when the issue happened?',
                ),
                validator: (v) => (v ?? '').trim().length < 10
                    ? 'Describe the issue in at least 10 characters'
                    : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your draft includes your Pulse account name, @username, linked account email (if available), app version and platform. Do not include passwords, verification codes or secret keys. Your email address and anything you send will be visible to the support mailbox.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy ? null : email,
                icon: const Icon(Icons.mail_outline),
                label: Text(busy ? 'Opening…' : 'Open support email'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => copy(),
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy message instead'),
              ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(notice!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
