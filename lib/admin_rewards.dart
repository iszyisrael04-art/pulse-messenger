import 'event_branding.dart';
import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'text_prompt.dart';

class PulseAdminRewards extends StatefulWidget {
  const PulseAdminRewards({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseAdminRewards> createState() => _PulseAdminRewardsState();
}

class _PulseAdminRewardsState extends State<PulseAdminRewards> {
  Map data = {};
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.repo.rpc('staff_rewards', {
        'p_action': 'overview',
      });
      if (mounted) setState(() => data = r as Map);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  Future<String?> input(String title) =>
      showPulseTextPrompt(context, title, maxLines: 1);
  Future<void> run(String action, Map<String, dynamic> values) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.repo.rpc('staff_rewards', {
        'p_action': action,
        'p_data': values,
      });
      if (mounted)
        setState(
          () => message = r['code'] == null
              ? 'Saved.'
              : 'Copy this code now: ${r['code']}',
        );
      await load();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create(String kind) async {
    final amount = int.tryParse(
      await input(
            kind == 'coins'
                ? 'Coin amount (1–100000)'
                : 'Promotion views per video (1–100000)',
          ) ??
          '',
    );
    if (amount == null || !mounted) return;
    final uses = int.tryParse(await input('Maximum users (1–1000)') ?? '');
    if (uses == null || !mounted) return;
    final days = int.tryParse(
      await input('Code expires after days (1–365)') ?? '',
    );
    if (days == null || !mounted) return;
    final duration = kind == 'views'
        ? int.tryParse(
            await input('Promotion lasts days after redemption (1–365)') ?? '',
          )
        : days;
    if (duration == null || !mounted) return;
    final announce = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Visible to everyone?'),
        content: const Text(
          'Public: show this code in Pulse Mail and notify all users with an unread bubble. Private: create without an announcement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Private · No mail'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Public · Notify everyone'),
          ),
        ],
      ),
    );
    if (announce == null) return;
    await run('create', {
      'public': announce,
      'kind': kind,
      'amount': amount,
      'max_uses': uses,
      'days': days,
      'reward_days': duration,
    });
  }

  Future<void> chooseAdmin() async {
    final username = await input('Exact Pulse username to make administrator');
    if (username == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Give @$username administrator access?'),
        content: const Text(
          'This grants account moderation and reward-code creation privileges.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Grant access'),
          ),
        ],
      ),
    );
    if (yes == true) await run('grant_admin', {'username': username});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administrators & reward codes')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  try {
                    await editPulseEventBranding(context, widget.repo);
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => message =
                            'Event logo could not be saved. Check staff access, image and duration.',
                      );
                  }
                },
          icon: const Icon(Icons.celebration_outlined),
          label: const Text('Change Pulse icons'),
        ),

        if (busy) const LinearProgressIndicator(),
        if (message != null) SelectableText(message!),
        if (data['owner'] == true)
          FilledButton.icon(
            onPressed: busy ? null : chooseAdmin,
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text('Choose administrator'),
          ),
        for (final a in data['administrators'] as List? ?? [])
          ListTile(
            title: Text('@${a['username']}'),
            subtitle: Text(a['owner'] == true ? 'Owner' : 'Administrator'),
            trailing: data['owner'] == true && a['owner'] != true
                ? IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Remove administrator',
                    onPressed: busy
                        ? null
                        : () =>
                              run('remove_admin', {'username': a['username']}),
                  )
                : null,
          ),
        const Divider(),
        const Text(
          'Each code can be redeemed once per user. Code expiry limits when it can be claimed. Coin rewards do not expire after claiming. View rewards activate a limited promotion, not fabricated views.',
        ),
        FilledButton(
          onPressed: busy ? null : () => create('coins'),
          child: const Text('Make coin code'),
        ),
        FilledButton(
          onPressed: busy ? null : () => create('views'),
          child: const Text('Make promotion-view code'),
        ),
        for (final c in data['codes'] as List? ?? [])
          ListTile(
            title: Text('${c['kind']} · ${c['amount']}'),
            subtitle: Text(
              '${c['uses']}/${c['max_uses']} used · expires ${c['expires_at']}',
            ),
            trailing: c['disabled'] == true
                ? const Text('Disabled')
                : TextButton(
                    onPressed: busy
                        ? null
                        : () => run('disable', {'id': c['id']}),
                    child: const Text('Disable'),
                  ),
          ),
      ],
    ),
  );
}

Future<void> redeemPulseReward(
  BuildContext context,
  PulseRepository repo,
) async {
  final code = await showPulseTextPrompt(
    context,
    'Redeem reward code',
    maxLines: 1,
  );
  if (code == null) return;
  try {
    final r = await repo.rpc('claim_reward', {'p_code': code});
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['amount']} ${r['kind']}. ${r['message']}')),
      );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code unavailable, already used or expired.'),
        ),
      );
  }
}
