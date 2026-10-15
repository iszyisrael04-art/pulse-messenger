import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'social_repository.dart';
import 'social_common.dart';
import 'social_download.dart';

Future<void> pulseContentContext(
  BuildContext context,
  SocialStore store,
  SocialRow post,
  Offset position,
  ValueChanged<SocialRow?> onChanged,
) async {
  final screen = MediaQuery.sizeOf(context);
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      screen.width - position.dx,
      screen.height - position.dy,
    ),
    items: [
      if ((post['media'] as List).isNotEmpty)
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.download_outlined),
            title: Text('Download'),
          ),
        ),
      const PopupMenuItem(
        value: 'save',
        child: ListTile(
          leading: Icon(Icons.bookmark_border),
          title: Text('Save / unsave'),
        ),
      ),
      const PopupMenuItem(
        value: 'copy',
        child: ListTile(leading: Icon(Icons.copy), title: Text('Copy post ID')),
      ),
      if (post['author_id'] == store.uid)
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
          ),
        )
      else
        const PopupMenuItem(
          value: 'report',
          child: ListTile(
            leading: Icon(Icons.flag_outlined),
            title: Text('Report'),
          ),
        ),
    ],
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'download')
      await downloadPulsePost(context, store, post['id']);
    if (choice == 'copy')
      await Clipboard.setData(ClipboardData(text: post['id']));
    if (choice == 'save')
      await store.action(post['id'], 'save', post['saved'] != true);
    if (choice == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete this content?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes == true) await store.edit(post['id'], '', delete: true);
    }
    if (choice == 'report' && context.mounted) {
      final reason = await socialPrompt(
        context,
        'Report this content',
        limit: 1000,
      );
      if (reason != null && reason.trim().isNotEmpty)
        await store.rpc('report', {'p_id': post['id'], 'p_reason': reason});
    }
    onChanged(await store.post(post['id']));
  } catch (e) {
    if (context.mounted) socialNotice(context, e);
  }
}
