import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'repository.dart' hide Row;
import 'avatar.dart';
import 'social_common.dart';

class PulseCommunities extends StatefulWidget {
  const PulseCommunities({
    super.key,
    required this.repo,
    this.user,
    this.onChat,
  });
  final PulseRepository repo;
  final String? user;
  final ValueChanged<String>? onChat;
  @override
  State<PulseCommunities> createState() => _PulseCommunitiesState();
}

class _PulseCommunitiesState extends State<PulseCommunities> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  bool joinedOnly = false;
  String? error;
  final query = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.repo.rpc('communities', {
        'p_action': 'list',
        'p_user': widget.user,
        'p_data': {'query': query.text.trim()},
      });
      if (mounted)
        setState(() {
          rows =
              (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
                ..sort((a, b) {
                  final joinedA = a['role'] != 'none',
                      joinedB = b['role'] != 'none';
                  if (joinedA != joinedB) return joinedA ? -1 : 1;
                  return a['name'].toString().compareTo(b['name'].toString());
                });
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not load communities. The server upgrade may still be pending.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(Map row, String action) async {
    try {
      await widget.repo.rpc('communities', {
        'p_action': action,
        'p_chat': row['chat_id'],
      });
      await widget.repo.refresh();
      await load();
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  Future<void> create() async {
    final name = await socialPrompt(context, 'Community name', limit: 80);
    if (name == null || !mounted) return;
    final handle = await socialPrompt(
      context,
      'Unique community handle (letters, numbers, underscore)',
      limit: 30,
    );
    if (handle == null || !mounted) return;
    try {
      await widget.repo.rpc('communities', {
        'p_action': 'create',
        'p_data': {'name': name, 'handle': handle.trim().toLowerCase()},
      });
      await widget.repo.refresh();
      await load();
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  Future<void> edit(Map row) async {
    final description = await socialPrompt(
      context,
      'Community description',
      initial: row['description'] ?? '',
      limit: 500,
    );
    if (description == null || !mounted) return;
    final privateChoice = await showDialog<bool>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Community visibility'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Public · visible on member profiles'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Private · visible only to members'),
          ),
        ],
      ),
    );
    if (privateChoice == null || !mounted) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    try {
      String? path = row['avatar_path'];
      if (file?.path != null)
        path = await widget.repo.upload(
          File(file!.path!),
          file.name,
          avatar: true,
        );
      await widget.repo.rpc('communities', {
        'p_action': 'update',
        'p_chat': row['chat_id'],
        'p_data': {
          'description': description,
          'avatar': path,
          'private': privateChoice,
        },
      });
      await load();
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Communities',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            if (widget.user == null)
              IconButton(
                onPressed: busy ? null : create,
                tooltip: 'Create community',
                icon: const Icon(Icons.group_add_outlined),
              ),
            IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          ],
        ),
      ),
      if (widget.user == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: query,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: 'Search communities',
              suffixIcon: IconButton(
                onPressed: load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
      if (widget.user == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('My communities'),
              selected: joinedOnly,
              onSelected: (v) => setState(() => joinedOnly = v),
            ),
          ),
        ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
      Expanded(
        child: ListView(
          children: [
            if (rows.where((r) => !joinedOnly || r['role'] != 'none').isEmpty &&
                !busy &&
                error == null)
              ListTile(
                title: Text(
                  joinedOnly
                      ? 'You have not joined a community yet.'
                      : 'No visible communities yet',
                ),
              ),
            for (final r in rows.where(
              (r) => !joinedOnly || r['role'] != 'none',
            ))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: PulseAvatar(
                    repo: widget.repo,
                    path: r['avatar_path'],
                    name: r['name'],
                    radius: 28,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (r['verified'] == true)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.verified,
                            size: 18,
                            color: Colors.blue,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${r['members']} members · ${r['description'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: r['role'] != 'none' && widget.onChat != null
                      ? () => widget.onChat!(r['chat_id'])
                      : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheet) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PulseAvatar(
                                    repo: widget.repo,
                                    path: r['avatar_path'],
                                    name: r['name'],
                                    radius: 44,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    r['name'],
                                    style: Theme.of(sheet).textTheme.titleLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    r['description'] ?? '',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  if (r['role'] == 'none')
                                    FilledButton(
                                      onPressed: () {
                                        Navigator.pop(sheet);
                                        action(
                                          r,
                                          r['request_state'] == 'pending'
                                              ? 'cancel'
                                              : 'request',
                                        );
                                      },
                                      child: Text(
                                        r['request_state'] == 'pending'
                                            ? 'Cancel join request'
                                            : 'Request to join',
                                      ),
                                    )
                                  else
                                    const Text('You are a member'),
                                ],
                              ),
                            ),
                          ),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((widget.repo.unread[r['chat_id']] ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Badge(
                            label: Text('${widget.repo.unread[r['chat_id']]}'),
                          ),
                        ),
                      PopupMenuButton<String>(
                        onSelected: (a) {
                          if (a == 'edit') {
                            edit(r);
                          } else if (a == 'open') {
                            widget.onChat?.call(r['chat_id']);
                          } else {
                            action(r, a);
                          }
                        },
                        itemBuilder: (_) => [
                          if (r['role'] == 'none')
                            PopupMenuItem(
                              value: r['request_state'] == 'pending'
                                  ? 'cancel'
                                  : 'request',
                              child: Text(
                                r['request_state'] == 'pending'
                                    ? 'Cancel join request'
                                    : 'Request to join',
                              ),
                            ),
                          if (r['role'] != 'none' && widget.onChat != null)
                            const PopupMenuItem(
                              value: 'open',
                              child: Text('Open chat'),
                            ),
                          if (['owner', 'admin'].contains(r['role']))
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit picture & description'),
                            ),
                          if (r['role'] == 'member' || r['role'] == 'admin')
                            const PopupMenuItem(
                              value: 'leave',
                              child: Text('Leave community'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class PulseProfileCommunities extends StatefulWidget {
  const PulseProfileCommunities({
    super.key,
    required this.repo,
    required this.user,
  });
  final PulseRepository repo;
  final String user;
  @override
  State<PulseProfileCommunities> createState() =>
      _PulseProfileCommunitiesState();
}

class _PulseProfileCommunitiesState extends State<PulseProfileCommunities> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = widget.repo.rpc('communities', {
      'p_action': 'list',
      'p_user': widget.user,
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (c, s) {
      final rows = s.data is List ? s.data as List : [];
      if (rows.isEmpty) return const SizedBox.shrink();
      void open() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Joined communities')),
            body: PulseCommunities(repo: widget.repo, user: widget.user),
          ),
        ),
      );
      if (rows.length >= 4)
        return OutlinedButton.icon(
          onPressed: open,
          icon: const Icon(Icons.groups_outlined),
          label: Text('Communities · ${rows.length}'),
        );
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in rows)
            ActionChip(
              onPressed: open,
              avatar: PulseAvatar(
                repo: widget.repo,
                path: r['avatar_path'],
                name: r['name'],
                radius: 13,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(r['name'], overflow: TextOverflow.ellipsis),
                  ),
                  if (r['verified'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(Icons.verified, size: 15, color: Colors.blue),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
