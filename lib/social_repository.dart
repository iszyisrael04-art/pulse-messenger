import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'media.dart';
import 'repository.dart' hide Row;

typedef SocialRow = Map<String, dynamic>;

String socialError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is StorageException) return error.message;
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
  final hiddenCreators = <String>{};
  final urls = LinkedHashMap<String, ({String url, DateTime expires})>();
  String get uid => repo.uid;
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
  }) async {
    final data = await rpc('feed', {
      'p_mode': mode,
      'p_kind': kind,
      'p_author': author,
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

  Future<String> upload(File file, String name, String postId) async {
    final mime = mimeFor(name);
    final kind = kindFor(mime);
    if (kind != 'image' && kind != 'video')
      throw SocialFailure('Choose a photo or video');
    final length = await file.length();
    final limit = kind == 'image' ? 10485760 : 41943040;
    if (length <= 0 || length > limit)
      throw SocialFailure('Photos must be under 10 MB; videos under 40 MB');
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/$postId/${const Uuid().v4()}-$safe';
    await repo.db.storage
        .from('pulse-social')
        .upload(path, file, fileOptions: FileOptions(contentType: mime));
    return path;
  }
}

class SocialFeedController extends ChangeNotifier {
  SocialFeedController(
    this.store, {
    this.mode = 'discovery',
    this.kind = 'all',
    this.author,
  });
  final SocialStore store;
  String mode, kind;
  String? author;
  List<SocialRow> rows = [];
  SocialRow? cursor;
  bool loading = false, hasMore = true, disposed = false;
  String? error;
  int generation = 0;
  Future<void> load({bool reset = false}) async {
    if (disposed || (!reset && (loading || !hasMore))) return;
    if (reset) {
      generation++;
      rows = [];
      cursor = null;
      hasMore = true;
    }
    final ownGeneration = generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await store.feed(
        mode: mode,
        kind: kind,
        author: author,
        cursor: cursor,
      );
      if (disposed || generation != ownGeneration) return;
      if (reset) rows = [];
      final ids = rows.map((r) => r['id']).toSet();
      rows.addAll(page.where((r) => ids.add(r['id'])));
      // Keep the server cursor even when duplicate rows were suppressed.
      if (page.isNotEmpty) cursor = page.last;
      hasMore = page.length == 12;
    } catch (e) {
      if (!disposed && generation == ownGeneration) error = socialError(e);
    } finally {
      if (!disposed && generation == ownGeneration) {
        loading = false;
        notifyListeners();
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
