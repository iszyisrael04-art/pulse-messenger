import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'repository.dart' hide Row;
import 'avatar.dart';
import 'social_repository.dart' show socialError;

Future<void> showChannelResponses(
  BuildContext context,
  PulseRepository repo,
  String post,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: .85,
    child: PulseChannelResponses(repo: repo, post: post),
  ),
);

class PulseChannelResponses extends StatefulWidget {
  const PulseChannelResponses({
    super.key,
    required this.repo,
    required this.post,
  });
  final PulseRepository repo;
  final String post;
  @override
  State<PulseChannelResponses> createState() => _PulseChannelResponsesState();
}

class _PulseChannelResponsesState extends State<PulseChannelResponses> {
  final text = TextEditingController();
  Map<String, dynamic> data = {};
  Map? reply;
  String? error, pendingId, pendingBody, pendingParent;
  bool busy = false, sending = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy || sending) return;
    setState(() => busy = true);
    try {
      final result = await widget.repo.rpc('channel_responses', {
        'p_post': widget.post,
      });
      if (mounted)
        setState(() {
          data = Map<String, dynamic>.from(result as Map);
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (sending || busy || text.text.trim().isEmpty) return;
    final body = text.text.trim(), parent = reply?['id'] as String?;
    if (pendingBody != body || pendingParent != parent) pendingId = null;
    pendingId ??= const Uuid().v4();
    pendingBody = body;
    pendingParent = parent;
    setState(() => sending = true);
    try {
      final result = await widget.repo.rpc('channel_responses', {
        'p_post': widget.post,
        'p_action': 'send',
        'p_id': pendingId,
        'p_body': body,
        'p_parent': parent,
      });
      if (mounted)
        setState(() {
          data = Map<String, dynamic>.from(result as Map);
          error = null;
          pendingId = null;
          reply = null;
          text.clear();
        });
    } catch (e) {
      if (mounted) setState(() => error = socialError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      children: [
        ListTile(
          title: Text('Responses · ${data['count'] ?? 0}'),
          trailing: IconButton(
            tooltip: 'Refresh responses',
            onPressed: busy || sending ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
        Expanded(
          child: ListView(
            children: [
              for (final r in data['items'] as List? ?? [])
                ListTile(
                  leading: PulseAvatar(
                    repo: widget.repo,
                    path: r['avatar_path'],
                    userId: r['user_id'],
                    name: r['display_name'],
                    radius: 18,
                  ),
                  title: Text(
                    r['display_name'] ?? r['username'] ?? 'Pulse user',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r['quoted_body'] != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          child: Text(
                            r['quoted_body'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Text(r['body']),
                    ],
                  ),
                  trailing: data['can_respond'] == true
                      ? IconButton(
                          tooltip: 'Reply to response',
                          onPressed: sending
                              ? null
                              : () => setState(() => reply = r as Map),
                          icon: const Icon(Icons.reply, size: 18),
                        )
                      : null,
                ),
              if ((data['items'] as List? ?? []).isEmpty && !busy)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Be the first to respond.'),
                ),
              if ((data['count'] as num? ?? 0) > 100)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Showing the latest 100 responses.'),
                ),
            ],
          ),
        ),
        if (reply != null)
          ListTile(
            dense: true,
            title: Text('Replying to ${reply!['display_name']}'),
            subtitle: Text(
              reply!['body'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              onPressed: sending ? null : () => setState(() => reply = null),
              icon: const Icon(Icons.close),
            ),
          ),
        if (data['can_respond'] == true)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    enabled: !sending,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Respond…',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send response',
                  onPressed: sending ? null : send,
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Follow this channel to respond.'),
          ),
      ],
    ),
  );
}
