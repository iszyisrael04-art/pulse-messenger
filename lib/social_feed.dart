import 'brand.dart';
import 'appearance.dart';
import 'package:flutter/material.dart';

import 'avatar.dart';
import 'social_repository.dart';
import 'social_create.dart';
import 'social_actions.dart';
import 'social_media.dart';
import 'social_common.dart';
import 'social_hashtags.dart';
import 'social_search.dart';

class SocialFeed extends StatefulWidget {
  const SocialFeed({
    super.key,
    required this.store,
    this.mode = 'discovery',
    this.author,
    this.kind = 'all',
    this.header = true,
    this.tag,
  });
  final SocialStore store;
  final String mode, kind;
  final String? author, tag;
  final bool header;
  @override
  State<SocialFeed> createState() => _SocialFeedState();
}

class _SocialFeedState extends State<SocialFeed> {
  late SocialFeedController feed;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    feed = SocialFeedController(
      widget.store,
      mode: widget.mode,
      author: widget.author,
      kind: widget.kind,
      tag: widget.tag,
    )..addListener(changed);
    feed.load(reset: true);
    scroll.addListener(() {
      if (scroll.hasClients && scroll.position.extentAfter < 700) feed.load();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SocialFeed old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode ||
        old.author != widget.author ||
        old.kind != widget.kind ||
        old.tag != widget.tag) {
      feed.mode = widget.mode;
      feed.author = widget.author;
      feed.kind = widget.kind;
      feed.tag = widget.tag;
      feed.load(reset: true);
    }
  }

  @override
  void dispose() {
    feed.removeListener(changed);
    feed.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> create({SocialRow? draft}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialComposer(store: widget.store, draft: draft),
      ),
    );
    if (saved == true && mounted) await feed.load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.header)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(
            children: [
              const PulseMark(size: 30),
              const SizedBox(width: 10),
              const Expanded(child: PulseWordmark(size: 30)),
              IconButton(
                tooltip: 'Search videos, hashtags and profiles',
                onPressed: () => openPulseSearch(context, widget.store),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Open post ID',
                onPressed: () async {
                  final value = await socialPrompt(
                    context,
                    'Paste a Pulse post ID',
                    limit: 80,
                  );
                  if (value == null || !mounted) return;
                  final match = RegExp(
                    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
                  ).firstMatch(value);
                  if (match == null) {
                    socialNotice(
                      context,
                      SocialFailure('Enter a valid post ID'),
                    );
                    return;
                  }
                  await openSocialPost(context, widget.store, match.group(0)!);
                },
                icon: const Icon(Icons.link),
              ),
              IconButton(
                tooltip: 'Create post',
                onPressed: create,
                icon: const Icon(Icons.add_box_outlined),
              ),
            ],
          ),
        ),
      if (widget.header)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              for (final entry in {
                'discovery': 'Discover',
                'following': 'Following',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      feed.mode = entry.key;
                      feed.load(reset: true);
                      if (scroll.hasClients) scroll.jumpTo(0);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: feed.mode == entry.key
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: feed.mode == entry.key
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 2,
                            width: 24,
                            color: feed.mode == entry.key
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => feed.load(reset: true),
          child: ListView.builder(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 200,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: feed.rows.length + 1,
            itemBuilder: (context, index) {
              if (index == feed.rows.length)
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      if (feed.loading)
                        const PulseLoader()
                      else if (feed.error != null) ...[
                        Text(feed.error!),
                        TextButton(
                          onPressed: () => feed.load(reset: feed.rows.isEmpty),
                          child: const Text('Retry'),
                        ),
                      ] else if (feed.rows.isEmpty)
                        Text(
                          feed.mode == 'following'
                              ? 'Follow creators to build your feed.'
                              : feed.mode == 'drafts'
                              ? 'No drafts yet. Create a post and choose Save draft.'
                              : 'No posts yet. Be the first to share something.',
                        )
                      else if (feed.hasMore)
                        TextButton(
                          onPressed: () => feed.load(),
                          child: const Text('Load more'),
                        )
                      else
                        const Text('You’re all caught up.'),
                    ],
                  ),
                );
              final post = feed.rows[index];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: post['state'] == 'draft'
                      ? Card(
                          child: ListTile(
                            leading: SizedBox(
                              width: 76,
                              height: 76,
                              child: (post['media'] as List).isEmpty
                                  ? const Icon(Icons.drafts_outlined)
                                  : SocialDraftCover(
                                      key: ValueKey(post['id']),
                                      store: widget.store,
                                      media: (post['media'] as List).first,
                                    ),
                            ),
                            title: Text(
                              post['body'].toString().isEmpty
                                  ? 'Media draft'
                                  : post['body'],
                            ),
                            subtitle: Text(post['kind']),
                            onTap: () => create(draft: post),
                            trailing: IconButton(
                              tooltip: 'Delete draft',
                              onPressed: () async {
                                try {
                                  await widget.store.edit(
                                    post['id'],
                                    '',
                                    delete: true,
                                  );
                                  feed.change(null, post['id']);
                                } catch (e) {
                                  if (context.mounted) socialNotice(context, e);
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        )
                      : SocialPostCard(
                          key: ValueKey(post['id']),
                          store: widget.store,
                          post: post,
                          onChanged: (updated) {
                            feed.change(updated, post['id']);
                          },
                        ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

class SocialPostPage extends StatefulWidget {
  const SocialPostPage({super.key, required this.store, required this.post});
  final SocialStore store;
  final SocialRow post;
  @override
  State<SocialPostPage> createState() => _SocialPostPageState();
}

class _SocialPostPageState extends State<SocialPostPage> {
  SocialRow? post;
  @override
  void initState() {
    super.initState();
    post = widget.post;
    widget.store.action(post!['id'], 'view', true).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pulse post')),
    body: post == null
        ? const Center(child: Text('Post unavailable'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: SocialPostCard(
                    store: widget.store,
                    post: post!,
                    details: true,
                    onChanged: (p) {
                      if (mounted) setState(() => post = p);
                    },
                  ),
                ),
              ),
            ],
          ),
  );
}

class SocialPostCard extends StatefulWidget {
  const SocialPostCard({
    super.key,
    required this.store,
    required this.post,
    required this.onChanged,
    this.details = false,
  });
  final SocialStore store;
  final SocialRow post;
  final ValueChanged<SocialRow?> onChanged;
  final bool details;
  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  int image = 0;
  @override
  Widget build(BuildContext context) {
    final post = widget.post,
        author = Map<String, dynamic>.from(post['author'] as Map);
    final media = (post['media'] as List).cast<Map>();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: PulseAvatar(
              repo: widget.store.repo,
              path: author['avatar_path'],
              name: author['display_name'],
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    author['display_name'],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (author['verified'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.verified, color: Colors.blue, size: 17),
                  ),
                if (author['premium'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.workspace_premium,
                      color: Colors.amber,
                      size: 17,
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '@${author['username'] ?? 'pulse_user'} · ${post['audience'] == 'followers' ? 'Followers' : 'Public'}\n${DateTime.parse(post['created_at']).toLocal().toString().substring(0, 16)}',
            ),
            onTap: () => openCreator(context, widget.store, post['author_id']),
          ),
          if (post['body'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(post['body']),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SocialHashtags(store: widget.store, body: post['body']),
          ),
          if (media.isNotEmpty && media.first['kind'] == 'image') ...[
            SizedBox(
              height: 320,
              child: PageView.builder(
                itemCount: media.length,
                onPageChanged: (v) => setState(() => image = v),
                itemBuilder: (_, i) =>
                    SocialImage(store: widget.store, path: media[i]['path']),
              ),
            ),
            if (media.length > 1)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text('${image + 1} / ${media.length} photos'),
                ),
              ),
          ],
          if (media.isNotEmpty && media.first['kind'] == 'video')
            SizedBox(
              height: 340,
              child: SocialInlineVideo(
                store: widget.store,
                postId: post['id'],
                path: media.first['path'],
              ),
            ),
          SocialActions(
            store: widget.store,
            post: post,
            onChanged: widget.onChanged,
          ),
          if (!widget.details)
            TextButton(
              onPressed: () =>
                  openSocialPost(context, widget.store, post['id']),
              child: const Text('View details'),
            ),
        ],
      ),
    );
  }
}
