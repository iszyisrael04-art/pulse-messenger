import 'package:flutter/material.dart';
import 'repository.dart' hide Row;
import 'avatar.dart';

class PulseControlCommunities extends StatefulWidget {
  const PulseControlCommunities({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseControlCommunities> createState() =>
      _PulseControlCommunitiesState();
}

class _PulseControlCommunitiesState extends State<PulseControlCommunities> {
  final query = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy || !reset && !more) return;
    setState(() => busy = true);
    try {
      final data = await widget.repo.rpc('community_verification', {
        'p_action': 'list',
        'p_query': query.text.trim(),
        'p_after': reset || rows.isEmpty ? null : rows.last['chat_id'],
      });
      if (mounted)
        setState(() {
          final page = (data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (reset) rows = [];
          rows.addAll(page);
          more = page.length == 50;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not load communities. Staff access and the server update are required.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify(Map<String, dynamic> row) async {
    if (busy) return;
    final enabled = row['verified'] != true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(enabled ? 'Verify community?' : 'Remove verification?'),
        content: Text(row['name']),
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
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repo.rpc('community_verification', {
        'p_action': 'set',
        'p_chat': row['chat_id'],
        'p_enabled': enabled,
      });
      if (mounted) setState(() => row['verified'] = enabled);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification update failed. Check staff permission and connection.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Community verification')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: query,
            maxLength: 40,
            onSubmitted: (_) => load(reset: true),
            decoration: InputDecoration(
              hintText: 'Search communities',
              counterText: '',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: busy ? null : () => load(reset: true),
                icon: const Icon(Icons.arrow_forward),
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
              if (rows.isEmpty && !busy && error == null)
                const ListTile(title: Text('No communities found')),
              for (final row in rows)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  leading: PulseAvatar(
                    repo: widget.repo,
                    path: row['avatar_path'],
                    name: row['name'],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (row['verified'] == true)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text('!${row['handle']}'),
                  trailing: IconButton(
                    tooltip: row['verified'] == true
                        ? 'Unverify community'
                        : 'Verify community',
                    onPressed: busy ? null : () => verify(row),
                    icon: Icon(
                      row['verified'] == true
                          ? Icons.verified
                          : Icons.verified_outlined,
                      color: row['verified'] == true ? Colors.blue : null,
                    ),
                  ),
                ),
              if (more && rows.isNotEmpty)
                TextButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
