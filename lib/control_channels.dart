import 'text_prompt.dart';
import 'package:flutter/material.dart';
import 'avatar.dart';
import 'repository.dart' hide Row;

class PulseControlChannels extends StatefulWidget {
  const PulseControlChannels({super.key, required this.repo});
  final PulseRepository repo;
  @override
  State<PulseControlChannels> createState() => _PulseControlChannelsState();
}

class _PulseControlChannelsState extends State<PulseControlChannels> {
  final search = TextEditingController();
  List<Map<String, dynamic>> channels = [];
  bool loading = false, changing = false, more = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading || !reset && !more) return;
    setState(() => loading = true);
    try {
      if (await widget.repo.rpc('is_admin', {}) != true) {
        throw StateError('Staff access required');
      }
      final term = search.text
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      var query = widget.repo.db
          .from('pulse_channels')
          .select('id,name,description,avatar_path,verified')
          .ilike('name', '%$term%');
      if (!reset && channels.isNotEmpty)
        query = query.gt('id', channels.last['id']);
      final rows = await query.order('id').limit(50);
      if (!mounted) return;
      setState(() {
        if (reset) channels = [];
        channels.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
        more = rows.length == 50;
        error = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not load channels. Check your connection and staff access.',
        );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verify(Map<String, dynamic> channel) async {
    if (changing || loading) return;
    final enabled = channel['verified'] != true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          enabled ? 'Verify channel?' : 'Remove channel verification?',
        ),
        content: Text(channel['name']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || changing) return;
    setState(() => changing = true);
    try {
      await widget.repo.rpc('admin_action', {
        'p_action': 'verify_channel',
        'p_data': {'id': channel['id'], 'verified': enabled},
      });
      if (mounted) {
        setState(() => channel['verified'] = enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Channel verified' : 'Channel verification removed',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update verification. Check your connection and staff access.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> deleteChannel(Map<String, dynamic> channel) async {
    if (changing || loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Permanently delete channel?'),
        content: Text(
          '${channel['name']} and its posts, followers and channel history '
          'will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete channel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || changing) return;
    setState(() => changing = true);
    try {
      await widget.repo.rpc('channel_delete', {'p_channel': channel['id']});
      if (!mounted) return;
      setState(() => channels.removeWhere((c) => c['id'] == channel['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Channel deleted')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Channel was not deleted. Check your connection and Pulse administrator access.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> livePolicy() async {
    try {
      final current =
          await widget.repo.rpc('live_tools', {'p_action': 'policy'}) as Map;
      if (!mounted) return;
      final value = await showPulseTextPrompt(
        context,
        'LIVE follower minimum',
        initial: '${current['min_followers']}',
        maxLength: 7,
        maxLines: 1,
        keyboardType: TextInputType.number,
        helperText:
            'Applies to personal user accounts. 0 removes the follower requirement.',
        actionLabel: 'Save for all users',
        validator: (v) {
          final n = int.tryParse(v);
          return n == null || n < 0 || n > 1000000
              ? 'Enter a number from 0 to 1,000,000.'
              : null;
        },
      );
      if (value == null) return;
      final minimum = int.parse(value);
      await widget.repo.rpc('live_tools', {
        'p_action': 'policy_save',
        'p_data': {'min_followers': minimum},
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Users now need $minimum followers to start LIVE.'),
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update the LIVE policy. Check staff access and connection.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Manage channels'),
      actions: [
        IconButton(
          tooltip: 'LIVE follower minimum',
          onPressed: livePolicy,
          icon: const Icon(Icons.live_tv_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.live_tv_outlined),
          title: const Text('LIVE follower requirement'),
          subtitle: const Text(
            'Set the minimum profile followers a user needs to broadcast.',
          ),
          trailing: TextButton(
            onPressed: livePolicy,
            child: const Text('Change'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: search,
            maxLength: 80,
            onSubmitted: (_) => load(reset: true),
            decoration: InputDecoration(
              hintText: 'Search channels',
              counterText: '',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search channels',
                onPressed: loading || changing ? null : () => load(reset: true),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        if (loading || changing) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(20), child: Text(error!)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (channels.isEmpty && !loading && error == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No channels found')),
                  ),
                for (final c in channels)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    leading: PulseAvatar(
                      repo: widget.repo,
                      path: c['avatar_path'],
                      name: c['name'],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (c['verified'] == true) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        c['description'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: !loading && !changing,
                      tooltip: 'Channel actions',
                      onSelected: (value) {
                        if (value == 'verify') verify(c);
                        if (value == 'delete') deleteChannel(c);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'verify',
                          child: Text(
                            c['verified'] == true
                                ? 'Remove verification'
                                : 'Verify channel',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete channel'),
                        ),
                      ],
                    ),
                  ),
                if (more && channels.isNotEmpty)
                  TextButton(
                    onPressed: loading || changing ? null : () => load(),
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
