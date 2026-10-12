import 'appearance.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'avatar.dart';
import 'media.dart';
import 'social_repository.dart';
import 'social_feed.dart';
import 'social_common.dart';
import 'social_hashtags.dart';

Future<void> openPulseSearch(BuildContext context, SocialStore store) async {
  await PulseMedia.pauseAll();
  if (context.mounted)
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => SocialSearchPage(store: store)),
    );
}

class SocialSearchPage extends StatefulWidget {
  const SocialSearchPage({super.key, required this.store});
  final SocialStore store;
  @override
  State<SocialSearchPage> createState() => _SocialSearchPageState();
}

class _SocialSearchPageState extends State<SocialSearchPage> {
  final query = TextEditingController();
  final scroll = ScrollController();
  Timer? debounce;
  int generation = 0, suggestionGeneration = 0;
  String mode = 'video', submitted = '';
  String? error;
  bool busy = false, suggesting = false, showSuggestions = false, more = false;
  List<SocialRow> rows = [], suggestions = [];
  SocialRow? cursor;
  @override
  void initState() {
    super.initState();
    query.addListener(changed);
    scroll.addListener(() {
      if (scroll.hasClients &&
          scroll.position.extentAfter < 600 &&
          more &&
          !busy)
        load();
    });
    load(reset: true);
  }

  @override
  void dispose() {
    generation++;
    suggestionGeneration++;
    debounce?.cancel();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  List<SocialRow> maps(dynamic value) =>
      (value as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
  void changed() {
    debounce?.cancel();
    final own = ++suggestionGeneration;
    final text = query.text.trim();
    setState(() {
      suggestions = [];
      showSuggestions = text.isNotEmpty;
      suggesting = text.length >= 2;
    });
    if (text.length < 2) return;
    debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final value = await widget.store.rpc('suggestions', {'p_query': text});
        if (mounted && suggestionGeneration == own)
          setState(() => suggestions = maps(value));
      } catch (_) {
        /* Search remains available when suggestions are offline. */
      } finally {
        if (mounted && suggestionGeneration == own)
          setState(() => suggesting = false);
      }
    });
  }

  Future<void> search() async {
    debounce?.cancel();
    suggestionGeneration++;
    submitted = query.text.trim();
    if (submitted.length > 100) return;
    setState(() {
      showSuggestions = false;
      suggestions = [];
    });
    FocusScope.of(context).unfocus();
    await load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && (busy || !more)) return;
    if (reset) {
      generation++;
      rows = [];
      cursor = null;
      more = false;
    }
    final own = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      dynamic value;
      if (submitted.isEmpty) {
        value = await widget.store.rpc('trending', {});
      } else if (mode == 'profile') {
        value = await widget.store.rpc('search_people', {'p_query': submitted});
      } else if (mode == 'hashtag') {
        value = await widget.store.rpc('suggestions', {'p_query': submitted});
        value = (value as List).where((x) => x['kind'] == 'hashtag').toList();
      } else {
        value = await widget.store.rpc('search', {
          'p_query': submitted,
          'p_kind': mode,
          'p_before': cursor?['created_at'],
          'p_cursor': cursor?['id'],
          'p_limit': 12,
        });
      }
      if (!mounted || own != generation) return;
      final page = maps(value);
      final ids = rows.map((x) => x['id'] ?? x['text']).toSet();
      rows.addAll(page.where((x) => ids.add(x['id'] ?? x['text'])));
      if (page.isNotEmpty) cursor = page.last;
      more =
          submitted.isNotEmpty &&
          mode != 'profile' &&
          mode != 'hashtag' &&
          page.length == 12;
    } catch (e) {
      if (mounted && own == generation) error = socialError(e);
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
    }
  }

  Future<void> choose(SocialRow s) async {
    if (s['kind'] == 'hashtag') {
      await openHashtag(
        context,
        widget.store,
        s['text'].toString().substring(1),
      );
      return;
    }
    query.text = s['text'];
    mode = s['kind'] == 'profile' ? 'profile' : 'video';
    await search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search PULSE')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: query,
            maxLength: 100,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              hintText: 'Videos, hashtags, profiles…',
              suffixIcon: IconButton(
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final entry in {
                'video': 'Videos',
                'all': 'Posts',
                'hashtag': 'Hashtags',
                'profile': 'Profiles',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: mode == entry.key,
                    onSelected: (_) {
                      mode = entry.key;
                      search();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (!showSuggestions && submitted.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Trending videos · unique views in the last 7 days'),
          ),
        Expanded(
          child: showSuggestions
              ? ListView(
                  children: [
                    if (suggesting) const LinearProgressIndicator(),
                    for (final s in suggestions)
                      ListTile(
                        leading: Icon(
                          s['kind'] == 'profile'
                              ? Icons.person_outline
                              : s['kind'] == 'hashtag'
                              ? Icons.tag
                              : Icons.search,
                        ),
                        title: Text(s['text']),
                        onTap: () => choose(s),
                      ),
                    if (!suggesting && suggestions.isEmpty)
                      ListTile(
                        title: Text('Search for “${query.text}”'),
                        onTap: search,
                      ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: () => load(reset: true),
                  child: ListView.builder(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length + 1,
                    itemBuilder: (c, i) {
                      if (i == rows.length)
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              if (busy)
                                const PulseLoader()
                              else if (error != null) ...[
                                Text(error!),
                                TextButton(
                                  onPressed: () => load(reset: rows.isEmpty),
                                  child: const Text('Retry'),
                                ),
                              ] else if (rows.isEmpty)
                                const Text('No results yet.')
                              else if (more)
                                TextButton(
                                  onPressed: load,
                                  child: const Text('Load more'),
                                ),
                            ],
                          ),
                        );
                      final r = rows[i];
                      if (mode == 'profile' && submitted.isNotEmpty)
                        return ListTile(
                          leading: PulseAvatar(
                            repo: widget.store.repo,
                            path: r['avatar_path'],
                            name: r['display_name'],
                          ),
                          title: Text(r['display_name']),
                          subtitle: Text('@${r['username'] ?? ''}'),
                          onTap: () =>
                              openCreator(context, widget.store, r['id']),
                        );
                      if (mode == 'hashtag' && submitted.isNotEmpty)
                        return ListTile(
                          leading: const Icon(Icons.tag),
                          title: Text(r['text']),
                          onTap: () => choose(r),
                        );
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: SocialPostCard(
                            key: ValueKey(r['id']),
                            store: widget.store,
                            post: r,
                            onChanged: (updated) {
                              if (mounted)
                                setState(() {
                                  if (updated == null ||
                                      widget.store.hiddenCreators.contains(
                                        r['author_id'],
                                      )) {
                                    rows.removeWhere(
                                      (x) =>
                                          x['id'] == r['id'] ||
                                          widget.store.hiddenCreators.contains(
                                            x['author_id'],
                                          ),
                                    );
                                  } else {
                                    rows[i] = updated;
                                  }
                                });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
