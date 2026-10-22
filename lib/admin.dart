import 'text_prompt.dart';
import 'control.dart';
import 'control_channels.dart';
import 'control_communities.dart';
import 'package:flutter/material.dart';

import 'repository.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? overview;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final value = await widget.repo.rpc('admin_overview', {});
      if (mounted)
        setState(() {
          overview = Map<String, dynamic>.from(value as Map);
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Administrator access required or service unavailable.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> input(String title) =>
      showPulseTextPrompt(context, title, maxLines: 1, allowEmpty: true);

  Future<void> action(String action, Map<String, dynamic> data) async {
    try {
      await widget.repo.rpc('admin_action', {
        'p_action': action,
        'p_data': data,
      });
      await load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Action rejected. Check values and administrator access.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pulse administration'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : overview == null
        ? Center(child: Text(error ?? 'Unavailable'))
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Verification & accounts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Find a Pulse username to add or remove its verified badge.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PulseControl(repo: widget.repo),
                  ),
                ),
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Manage user verification'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PulseControlChannels(repo: widget.repo),
                  ),
                ),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Manage channel verification'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PulseControlCommunities(repo: widget.repo),
                  ),
                ),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Manage community verification'),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: ['users', 'messages', 'groups', 'channels']
                    .map(
                      (k) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                '${overview![k]}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              Text(k),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              Text(
                'Account reports',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final r in overview!['reports'] as List)
                ListTile(
                  title: Text(r['reason']),
                  subtitle: Text('Account ${r['reported_id']} · ${r['state']}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) =>
                        action('report', {'id': r['id'], 'state': v}),
                    itemBuilder: (_) => ['open', 'reviewed', 'closed']
                        .map((s) => PopupMenuItem(value: s, child: Text(s)))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Public channels',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final c in widget.repo.channels)
                SwitchListTile(
                  title: Text(c['name']),
                  subtitle: const Text('Verified channel badge'),
                  value: c['verified'] == true,
                  onChanged: (v) async {
                    await action('verify_channel', {
                      'id': c['id'],
                      'verified': v,
                    });
                    await widget.repo.refresh();
                    if (mounted) setState(() {});
                  },
                ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  final body = await input('App announcement');
                  if (body != null && body.isNotEmpty)
                    await action('announcement', {'body': body});
                },
                icon: const Icon(Icons.campaign),
                label: const Text('Publish app announcement'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final key = await input('Feature flag key');
                  if (key == null || key.isEmpty) return;
                  final enabled = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text('Enable $key?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Disable'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  );
                  if (enabled != null)
                    await action('flag', {'key': key, 'value': enabled});
                },
                icon: const Icon(Icons.flag),
                label: const Text('Set a feature flag'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Manage user verification also includes suspension, bans and restoring account access. Feature flags are stored; rollout evaluation is not implemented yet.',
                ),
              ),
            ],
          ),
  );
}
