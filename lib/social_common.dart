import 'text_prompt.dart';
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
}) => showPulseTextPrompt(
  context,
  title,
  initial: initial,
  maxLength: limit,
  minLines: 2,
  maxLines: 6,
  allowEmpty: true,
);

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
