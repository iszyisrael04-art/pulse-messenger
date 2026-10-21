import 'dart:collection';
import 'interests.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'media.dart';
import 'social_upload.dart';
import 'activity_controller.dart';
import 'repository.dart' hide Row;

typedef SocialRow = Map<String, dynamic>;

String socialError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is StorageException) return error.message;
  if (error is HttpException) return error.message;
  if (error is SocialFailure) return error.message;
  return 'Connection unavailable. Please retry.';
}

class SocialFailure implements Exception {
  SocialFailure(this.message);
  final String message;
}

class SocialStore {
  SocialStore(this.repo);
  final PulseRepository repo;
  late final activity = PulseActivityController(repo);
  final hiddenCreators = <String>{};
  final urls = LinkedHashMap<String, ({String url, DateTime expires})>();
  String get uid => repo.uid;
  List<String> get interests => pulseInterests(
    repo.db.auth.currentUser?.userMetadata?['pulse_interests'],
  );
  bool get interestsChosen =>
      repo.db.auth.currentUser?.userMetadata?['pulse_interests_chosen'] == true;
  Future<void> saveInterests(List<String> values) async {
    await repo.db.auth.updateUser(
      UserAttributes(
        data: {
          'pulse_interests': pulseInterests(values),
          'pulse_interests_chosen': true,
        },
      ),
    );
  }

  Future<dynamic> rpc(String name, SocialRow values) =>
      repo.rpc('social_$name', values);
  Future<SocialRow?> post(String id) async {
    final value = await rpc('post', {'p_id': id});
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<List<SocialRow>> feed({
    String mode = 'discovery',
    String kind = 'all',
    String? author,
    SocialRow? cursor,
    String? tag,
  }) async {
    final data = await rpc(tag == null ? 'feed' : 'tag_feed', {
      if (tag == null) 'p_mode': mode,
      'p_kind': kind,
      if (tag == null) 'p_author': author,
      if (tag != null) 'p_tag': tag,
      'p_before': cursor?['created_at'],
      'p_cursor': cursor?['id'],
      'p_limit': 12,
    });
    return (data as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
  }

  Future<String> signed(String path, {bool renew = false}) async {
    final cached = urls[path];
    if (!renew && cached != null && cached.expires.isAfter(DateTime.now()))
      return cached.url;
    final url = await repo.db.storage
        .from('pulse-social')
        .createSignedUrl(path, 300);
    urls.remove(path);
    urls[path] = (
      url: url,
      expires: DateTime.now().add(const Duration(seconds: 45)),
    );
    while (urls.length > 40) {
      urls.remove(urls.keys.first);
    }
    return url;
  }

  Future<SocialRow> profile(String user) async {
    final result = await rpc('profile', {'p_user': user});
    if (result == null) throw SocialFailure('Profile unavailable');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> follow(String user, bool enabled) async =>
      await rpc('follow', {'p_user': user, 'p_follow': enabled}) as String;
  Future<void> action(String id, String action, bool enabled) async {
    await rpc('action', {'p_id': id, 'p_action': action, 'p_enabled': enabled});
  }

  Future<void> edit(String id, String body, {bool delete = false}) async {
    await rpc('edit', {'p_id': id, 'p_body': body, 'p_delete': delete});
  }

  Future<void> share(String id, String chat) async {
    await rpc('share', {
      'p_post': id,
      'p_chat': chat,
      'p_message': const Uuid().v4(),
    });
    await repo.refresh();
  }

  Future<void> block(String user) async {
    await repo.rpc('block_user', {'p_user': user, 'p_block': true});
    hiddenCreators.add(user);
    urls.clear();
    await repo.refresh();
  }

  Future<SocialRow> uploadAccess(int bytes) async => Map<String, dynamic>.from(
    await rpc('upload_access', {'p_bytes': bytes}) as Map,
  );

  Future<String> upload(
    File file,
    String name,
    String postId, {
    void Function(double)? progress,
  }) async {
    final mime = mimeFor(name);
    final kind = kindFor(mime);
    if (kind != 'image' && kind != 'video')
      throw SocialFailure('Choose a photo or video');
    final access = await uploadAccess(await file.length());
    if (access['allowed'] != true)
      throw SocialFailure(
        access['premium'] == true
            ? 'File exceeds the current hosting maximum.'
            : 'Your file is over 500MB. Please upgrade to Premium to continue.',
      );
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/$postId/${const Uuid().v4()}-$safe';
    final base = Uri.parse(const String.fromEnvironment('SUPABASE_URL'));
    final endpoint = base.replace(
      host:
          base.host.endsWith('.supabase.co') &&
              !base.host.endsWith('.storage.supabase.co')
          ? '${base.host.split('.').first}.storage.supabase.co'
          : base.host,
      path: '/storage/v1/upload/resumable',
      query: null,
      fragment: null,
    );
    await PulseTusUploader(
      endpoint: endpoint,
      token: () async {
        final session = repo.db.auth.currentSession;
        if (session == null) throw SocialFailure('Sign in again to upload');
        if (session.isExpired) await repo.db.auth.refreshSession();
        return repo.db.auth.currentSession!.accessToken;
      },
    ).upload(file, path, mime, progress: progress);
    return path;
  }
}

class SocialFeedController extends ChangeNotifier {
  SocialFeedController(
    this.store, {
    this.mode = 'discovery',
    this.kind = 'all',
    this.author,
    this.tag,
  });
  final SocialStore store;
  String mode, kind;
  String? author, tag;
  List<SocialRow> rows = [];
  SocialRow? cursor;
  bool loading = false, hasMore = true, disposed = false;
  String? error;
  int generation = 0;
  bool discoveryMore = true;
  int interestTurn = 0, recommendationSeed = 0;
  final interestCursors = <String, SocialRow?>{};
  final exhaustedInterests = <String>{};
  Future<void> load({bool reset = false}) async {
    if (disposed || (!reset && (loading || !hasMore))) return;
    if (reset) {
      generation++;
      rows = [];
      cursor = null;
      discoveryMore = true;
      interestTurn = 0;
      recommendationSeed = DateTime.now().millisecondsSinceEpoch;
      interestCursors.clear();
      exhaustedInterests.clear();
      hasMore = true;
    }
    final ownGeneration = generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      List<SocialRow> page;
      if (mode == 'for_you' && tag == null && author == null) {
        final topics = store.interests
            .where((t) => !exhaustedInterests.contains(t))
            .toList();
        final topic = topics.isEmpty
            ? null
            : topics[interestTurn++ % topics.length];
        final discovery = discoveryMore
            ? await store.feed(mode: 'discovery', kind: kind, cursor: cursor)
            : <SocialRow>[];
        List<SocialRow> topical = [];
        if (topic != null) {
          topical = await store.feed(
            tag: topic,
            kind: kind,
            cursor: interestCursors[topic],
          );
        }
        if (disposed || generation != ownGeneration) return;
        if (discovery.isNotEmpty) cursor = discovery.last;
        discoveryMore = discovery.length == 12;
        if (topic != null) {
          if (topical.isNotEmpty) interestCursors[topic] = topical.last;
          if (topical.length < 12) exhaustedInterests.add(topic);
        }
        page = pulseRankForYou(
          [...topical, ...discovery],
          store.interests,
          recommendationSeed,
        );
        hasMore =
            discoveryMore ||
            store.interests.any((t) => !exhaustedInterests.contains(t));
      } else {
        page = await store.feed(
          mode: mode,
          kind: kind,
          author: author,
          cursor: cursor,
          tag: tag,
        );
        if (disposed || generation != ownGeneration) return;
        if (page.isNotEmpty) cursor = page.last;
        hasMore = page.length == 12;
      }
      if (reset) rows = [];
      final ids = rows.map((r) => r['id']).toSet();
      rows.addAll(page.where((r) => ids.add(r['id'])));
    } catch (e) {
      if (!disposed && generation == ownGeneration) error = socialError(e);
    } finally {
      if (!disposed && generation == ownGeneration) {
        loading = false;
        notifyListeners();
        if (mode == 'for_you' && rows.isEmpty && hasMore && error == null) {
          Future<void>.microtask(() => load());
        }
      }
    }
  }

  void change(SocialRow? post, String id) {
    final index = rows.indexWhere((r) => r['id'] == id);
    if (index < 0 || disposed) return;
    if (store.hiddenCreators.contains(rows[index]['author_id'])) {
      rows.removeWhere((r) => store.hiddenCreators.contains(r['author_id']));
    } else if (post != null &&
        mode == 'following' &&
        post['author_id'] != store.uid &&
        post['follow_state'] != 'accepted') {
      rows.removeWhere((r) => r['author_id'] == post['author_id']);
    } else if (post == null) {
      rows.removeAt(index);
    } else {
      rows[index] = post;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    super.dispose();
  }
}
