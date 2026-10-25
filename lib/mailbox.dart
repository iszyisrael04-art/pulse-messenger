import 'package:flutter/material.dart';
import 'repository.dart' hide Row;

class PulseMailbox extends StatefulWidget {
  const PulseMailbox({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseMailbox> createState() => _PulseMailboxState();
}

class _PulseMailboxState extends State<PulseMailbox> {
  Map data = {};
  List rewards = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.repo.rpc('inbox', {});
      final mail = await widget.repo.rpc('reward_mail', {});
      rewards = mail['items'] as List? ?? [];
      if (rewards.isNotEmpty)
        await widget.repo.rpc('reward_mail', {
          'p_seen': rewards.map((r) => r['id']).toList(),
        });
      if (mounted)
        setState(() {
          data = r as Map;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Inbox unavailable. Check your connection or pending server upgrade.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(String rpc, Map<String, dynamic> args) async {
    try {
      await widget.repo.rpc(rpc, args);
      await widget.repo.refresh();
      await load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action could not be completed. Please retry.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pulse mail & requests'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        Expanded(
          child: ListView(
            children: [
              if (rewards.isNotEmpty)
                const ListTile(
                  leading: Icon(Icons.redeem),
                  title: Text('Public reward codes'),
                ),
              for (final r in rewards)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.redeem),
                    title: SelectableText(r['code']),
                    subtitle: Text(
                      '${r['amount']} ${r['kind']} · expires ${r['expires_at']}\nRedeem in Shop. Limited availability.',
                    ),
                  ),
                ),
              const ListTile(title: Text('Community join requests')),
              for (final r in data['community_requests'] as List? ?? [])
                ListTile(
                  title: Text('${r['display_name']} · @${r['username']}'),
                  subtitle: Text('Wants to join ${r['community']}'),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check),
                        onPressed: () => act('communities', {
                          'p_action': 'approve',
                          'p_chat': r['chat_id'],
                          'p_user': r['user_id'],
                        }),
                      ),
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close),
                        onPressed: () => act('communities', {
                          'p_action': 'decline',
                          'p_chat': r['chat_id'],
                          'p_user': r['user_id'],
                        }),
                      ),
                    ],
                  ),
                ),
              const ListTile(title: Text('Message requests')),
              for (final r in data['chat_requests'] as List? ?? [])
                ListTile(
                  title: Text('${r['display_name']} · @${r['username']}'),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Accept',
                        icon: const Icon(Icons.check),
                        onPressed: () => act('respond_request', {
                          'p_chat': r['chat_id'],
                          'p_accept': true,
                        }),
                      ),
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close),
                        onPressed: () => act('respond_request', {
                          'p_chat': r['chat_id'],
                          'p_accept': false,
                        }),
                      ),
                    ],
                  ),
                ),
              const ListTile(title: Text('From Pulse')),
              for (final m in data['mail'] as List? ?? [])
                ListTile(
                  leading: Icon(
                    m['read_at'] == null
                        ? Icons.mark_email_unread_outlined
                        : Icons.drafts_outlined,
                  ),
                  title: Text(m['title']),
                  subtitle: Text(m['body']),
                  onTap: () => act('inbox', {
                    'p_action': 'read',
                    'p_data': {'id': m['id']},
                  }),
                ),
              for (final m in data['announcements'] as List? ?? [])
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(m['body']),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
