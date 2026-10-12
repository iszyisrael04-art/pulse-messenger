import 'package:flutter/material.dart';
import 'social_repository.dart';
import 'social_feed.dart';
import 'media.dart';

List<String> pulseHashtags(String text) {
  final tags = <String>{};
  for (final match in RegExp(
    r'#([A-Za-z0-9_]{1,64})(?![A-Za-z0-9_])',
  ).allMatches(text)) {
    tags.add(match.group(1)!.toLowerCase());
    if (tags.length == 20) break;
  }
  return tags.toList();
}

Future<void> openHashtag(
  BuildContext context,
  SocialStore store,
  String tag,
) async {
  await PulseMedia.pauseAll();
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SocialHashtagPage(store: store, initial: tag),
    ),
  );
}

class SocialHashtags extends StatelessWidget {
  const SocialHashtags({
    super.key,
    required this.store,
    required this.body,
    this.light = false,
  });
  final SocialStore store;
  final String body;
  final bool light;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (final tag in pulseHashtags(body))
        ActionChip(
          label: Text('#$tag'),
          onPressed: () => openHashtag(context, store, tag),
        ),
    ],
  );
}

class SocialHashtagPage extends StatefulWidget {
  const SocialHashtagPage({super.key, required this.store, this.initial = ''});
  final SocialStore store;
  final String initial;
  @override
  State<SocialHashtagPage> createState() => _SocialHashtagPageState();
}

class _SocialHashtagPageState extends State<SocialHashtagPage> {
  late final TextEditingController query;
  late String tag;
  String kind = 'all';
  String? error;
  @override
  void initState() {
    super.initState();
    tag = widget.initial;
    query = TextEditingController(text: tag);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void search() {
    final text = query.text
        .trim()
        .replaceFirst(RegExp(r'^#'), '')
        .toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(text)) {
      setState(
        () => error = 'Enter a hashtag using letters, numbers, or underscores.',
      );
      return;
    }
    setState(() {
      tag = text;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tag.isEmpty ? 'Find a hashtag' : '#$tag')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: query,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              prefixText: '#',
              hintText: 'Search hashtags',
              errorText: error,
              suffixIcon: IconButton(
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'post', label: Text('Posts')),
            ButtonSegment(value: 'reel', label: Text('Reels')),
          ],
          selected: {kind},
          onSelectionChanged: (v) => setState(() => kind = v.first),
        ),
        Expanded(
          child: tag.isEmpty
              ? const Center(
                  child: Text('Search a topic to discover posts and Reels.'),
                )
              : SocialFeed(
                  key: ValueKey('$tag:$kind'),
                  store: widget.store,
                  tag: tag,
                  kind: kind,
                  header: false,
                ),
        ),
      ],
    ),
  );
}
