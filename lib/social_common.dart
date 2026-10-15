import 'package:flutter/material.dart';

import 'media.dart';
import 'social_repository.dart';
import 'social_feed.dart';
import 'social_profile.dart';

void socialNotice(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(socialError(error))));
}

Future<String?> socialPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  int limit = 4000,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 6,
        maxLength: limit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<void> openSocialPost(
  BuildContext context,
  SocialStore store,
  String id,
) async {
  try {
    await PulseMedia.pauseAll();
    final post = await store.post(id);
    if (!context.mounted) return;
    if (post == null)
      throw SocialFailure(
        'This post was deleted, restricted or is unavailable.',
      );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialPostPage(store: store, post: post),
      ),
    );
  } catch (e) {
    if (context.mounted) socialNotice(context, e);
  }
}

Future<void> openCreator(
  BuildContext context,
  SocialStore store,
  String uid,
) async {
  await PulseMedia.pauseAll();
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Creator profile')),
        body: SocialProfile(store: store, user: uid),
      ),
    ),
  );
}
