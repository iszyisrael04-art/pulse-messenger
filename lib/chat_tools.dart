import 'package:flutter/material.dart';
import 'repository.dart';
import 'social_repository.dart';

class PulseChatTools extends StatefulWidget {
  const PulseChatTools({
    super.key,
    required this.repo,
    required this.store,
    required this.chat,
  });
  final PulseRepository repo;
  final SocialStore store;
  final String chat;
  @override
  State<PulseChatTools> createState() => _PulseChatToolsState();
}

class _PulseChatToolsState extends State<PulseChatTools> {
  final note = TextEditingController();
  List<Map<String, dynamic>> replies = [];
  bool busy = false, noteDirty = false, settingNote = false, confirming = false;
  String style = 'classic';
  String? error;
  @override
  void initState() {
    super.initState();
    note.addListener(() {
      if (!settingNote && !noteDirty && mounted)
        setState(() => noteDirty = true);
    });
    load();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<dynamic> api(
    String action, {
    String? id,
    String? label,
    String? text,
  }) => widget.repo
      .rpc('user_tools', {
        'p_action': action,
        'p_chat': widget.chat,
        'p_id': id,
        'p_label': label,
        'p_text': text,
      })
      .timeout(const Duration(seconds: 15));
  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await api('note_get');
      final quick = await api('quick_list');
      final theme = await api('style_get');
      if (mounted)
        setState(() {
          if (!noteDirty) {
            settingNote = true;
            note.text = saved['body'] as String;
            settingNote = false;
          }
          replies = (quick['items'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          style = theme['style'] as String;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Chat tools are unavailable. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not save. Check your connection and the 20-reply limit.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editReply([Map<String, dynamic>? reply]) async {
    final title = TextEditingController(text: reply?['label'] ?? '');
    final body = TextEditingController(text: reply?['body'] ?? '');
    final form = GlobalKey<FormState>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(reply == null ? 'New quick reply' : 'Edit quick reply'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter a title' : null,
                  ),
                  TextFormField(
                    controller: body,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Reply text'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter your reply' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await perform(() async {
        await api(
          'quick_save',
          id: reply?['id'],
          label: title.text.trim(),
          text: body.text.trim(),
        );
      });
      if (mounted && error == null) await load();
    }
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      title.dispose();
      body.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: PopScope(
      canPop: !busy && !noteDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || busy || !noteDirty || confirming) return;
        confirming = true;
        final discard = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Discard your unsaved Pocket note?'),
            content: const Text(
              'Save it first to keep it on your Pulse account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        confirming = false;
        if (discard == true && mounted) {
          noteDirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pulse chat studio'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pocket'),
              Tab(text: 'Replies'),
              Tab(text: 'Style'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'A private pocket for this conversation',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'This scratchpad is visible in your account and is never sent to chat participants. It syncs through your Pulse account. Notes are protected by access controls, not end-to-end encryption.',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: note,
                        enabled: !busy,
                        minLines: 6,
                        maxLines: 14,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          hintText:
                              'Remember a plan, an idea or what to ask next…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => perform(() async {
                                await api('note_save', text: note.text);
                                noteDirty = false;
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Private note saved.'),
                                    ),
                                  );
                              }),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save my note'),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'Saved quick replies',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Keep up to 20 reusable replies. Selecting a reply inserts a draft; you choose when to send it.',
                      ),
                      for (final r in replies)
                        Card(
                          child: ListTile(
                            title: Text(
                              r['label'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              r['body'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: busy
                                ? null
                                : () {
                                    perform(() async {
                                      final value = await api(
                                        'quick_use',
                                        id: r['id'],
                                      );
                                      if (mounted)
                                        Navigator.pop(
                                          context,
                                          value['body'] as String,
                                        );
                                    });
                                  },
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await editReply(r);
                                } else {
                                  await perform(() async {
                                    await api('quick_delete', id: r['id']);
                                  });
                                  if (mounted && error == null) await load();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: busy ? null : editReply,
                        icon: const Icon(Icons.add),
                        label: const Text('Create quick reply'),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'Your bubble style',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Customize outgoing bubbles for this conversation on your devices. Your friend keeps their own appearance.',
                      ),
                      for (final entry in {
                        'classic': 'Classic',
                        'aurora': 'Aurora mint',
                        'rose': 'Rose glow',
                        'ocean': 'Ocean blue',
                      }.entries)
                        ListTile(
                          title: Text(entry.value),
                          leading: Icon(
                            style == entry.key
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          onTap: busy
                              ? null
                              : () async {
                                  await perform(() async {
                                    await api('style_save', label: entry.key);
                                    await widget.repo.loadChatStyle(
                                      widget.chat,
                                    );
                                    if (mounted)
                                      setState(() => style = entry.key);
                                  });
                                },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
