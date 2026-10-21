import 'control_communities.dart';
import 'control_channels.dart';
import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'avatar.dart';
import 'social_common.dart';
import 'appeals.dart';

class PulseControl extends StatefulWidget {
  const PulseControl({super.key});
  @override
  State<PulseControl> createState() => _PulseControlState();
}

class _PulseControlState extends State<PulseControl> {
  late final repo = PulseRepository(Supabase.instance.client);
  final search = TextEditingController();
  List<Map<String, dynamic>> users = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    search.dispose();
    repo.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy || !reset && !more) return;
    setState(() => busy = true);
    try {
      final r = await repo.rpc('control', {
        'p_action': 'search',
        'p_data': {
          'query': search.text.trim(),
          'after': reset || users.isEmpty ? null : users.last['username'],
        },
      });
      if (mounted)
        setState(() {
          final page = (r as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (reset) users = [];
          users.addAll(page);
          more = page.length == 50;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Authorized Pulse staff account required. The server upgrade must also be deployed.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(Map u, String action) async {
    String? reason;
    int? days;
    if (action == 'ban' || action == 'suspend') {
      reason = await socialPrompt(
        context,
        'Reason for ${action == 'ban' ? 'ban' : 'suspension'}',
        limit: 1000,
      );
      if (reason == null || !mounted) return;
    }
    if (action == 'suspend') {
      final text = await socialPrompt(
        context,
        'Number of days (1–365)',
        limit: 3,
      );
      days = int.tryParse(text ?? '');
      if (days == null || days < 1 || days > 365) return;
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$action @${u['username']}?'),
        content: Text(
          'This changes the real Pulse account. ${days == null ? '' : 'Duration: $days days.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final r = await repo.rpc('control', {
        'p_action': action,
        'p_user': u['id'],
        'p_data': {'reason': reason, 'days': days},
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (r as Map)['email_queued'] == true
                  ? 'Account updated. Email queued; delivery requires the mail dispatcher.'
                  : 'Account updated. In-app mail created.',
            ),
          ),
        );
      await load(reset: true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Action denied. Check staff permission, reason and suspension duration.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pulse Control'),
      actions: [
        IconButton(
          tooltip: 'Verify communities',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PulseControlCommunities(repo: repo),
            ),
          ),
          icon: const Icon(Icons.groups_outlined),
        ),
        IconButton(
          tooltip: 'Verify channels',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PulseControlChannels(repo: repo)),
          ),
          icon: const Icon(Icons.campaign_outlined),
        ),
        IconButton(
          tooltip: 'Appeals',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PulseStaffAppeals(repo: repo)),
          ),
          icon: const Icon(Icons.gavel_outlined),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => repo.db.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            onSubmitted: (_) => load(reset: true),
            decoration: InputDecoration(
              labelText: 'Search Pulse usernames',
              prefixText: '@',
              suffixIcon: IconButton(
                onPressed: () => load(reset: true),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(
          child: ListView(
            children: [
              for (final u in users)
                ListTile(
                  leading: PulseAvatar(
                    repo: repo,
                    path: u['avatar_path'],
                    name: u['display_name'],
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          u['display_name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u['verified'] == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          size: 18,
                          color: Colors.blue,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '@${u['username']} · ${u['state']}\n${u['until_at'] ?? ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: u['verified'] == true
                            ? 'Remove verification'
                            : 'Verify account',
                        onPressed: () => action(
                          u,
                          u['verified'] == true ? 'unverify' : 'verify',
                        ),
                        icon: Icon(
                          u['verified'] == true
                              ? Icons.verified
                              : Icons.verified_outlined,
                          color: u['verified'] == true ? Colors.blue : null,
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => action(u, v),
                        itemBuilder: (_) => [
                          for (final v in [
                            'verify',
                            'unverify',
                            'ban',
                            'suspend',
                            'release',
                          ])
                            PopupMenuItem(value: v, child: Text(v)),
                        ],
                      ),
                    ],
                  ),
                ),
              if (more && users.isNotEmpty)
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Load more'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
