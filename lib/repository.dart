import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'notifications.dart';
import 'push.dart';
import 'presence.dart';
import 'profile_media_rules.dart';

typedef Row = Map<String, dynamic>;

class PulseRepository extends ChangeNotifier {
  PulseRepository(this.db);
  final SupabaseClient db;
  late final presence = PulsePresence(
    rpc: rpc,
    owner: () => uid,
    peers: () => profiles.keys,
  );
  static const vault = FlutterSecureStorage();
  final profiles = <String, Row>{};
  final messages = <Row>[];
  final pending = <Row>[];
  List<Row> chats = [],
      statuses = [],
      channels = [],
      followers = [],
      posts = [];
  List<Row> receipts = [], reactions = [], preferences = [], blocks = [];
  Row? me;
  List<Row> chatRequests = [];
  Map<String, int> unread = {};
  Map<String, Row> chatSummaries = {};
  Row? incoming;
  bool Function(String)? isChatVisible;
  final _announced = <String>{};
  DateTime? motionUntil;
  String chatStyle = 'classic';
  bool get motionActive => motionUntil?.isAfter(DateTime.now()) == true;
  Future<void> refreshCreatorAccess() async {
    final access = await rpc('creator_access', {});
    motionUntil = access['motion'] == true ? DateTime.utc(9999) : null;
    _avatarEntitlements.clear();
    notifyListeners();
  }

  int incomingSerial = 0;
  Row? requestFor(String? chat) =>
      chatRequests.where((r) => r['chat_id'] == chat).firstOrNull;
  bool canReply(String? chat) {
    final r = requestFor(chat);
    return r == null ||
        r['state'] == 'accepted' ||
        r['state'] == 'pending' && r['sender_id'] == uid;
  }

  String? activeChat, error;
  bool busy = false, syncing = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  RealtimeChannel? _realtime;
  Timer? _timer;
  int _generation = 0;
  String get uid => db.auth.currentUser!.id;
  String get _queueKey => 'pulse.outbox.$uid';
  String get _cacheKey => 'pulse.cache.$uid';

  Future<void> initialize() async {
    final saved = await vault.read(key: _queueKey);
    if (saved != null) pending.addAll((jsonDecode(saved) as List).cast<Row>());
    final cache = await vault.read(key: _cacheKey);
    if (cache != null) {
      final c = jsonDecode(cache) as Row;
      chats = (c['chats'] as List).cast<Row>();
      chatSummaries = {
        for (final row in (c['summaries'] as List? ?? []))
          row['chat_id'] as String: Map<String, dynamic>.from(row as Map),
      };
      for (final p in (c['profiles'] as List).cast<Row>()) {
        profiles[p['id']] = p;
      }
      me = profiles[uid];
    }
    if (_disposed || db.auth.currentUser == null) return;
    presence.start();
    await refresh();
    if (_disposed || db.auth.currentUser == null) return;
    PulsePush.instance.onMessage = (id) => unawaited(fetchIncoming(id));
    _realtime = db
        .channel('pulse:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_messages',
          callback: (change) {
            if (_disposed || db.auth.currentUser == null) return;
            if (change.eventType == PostgresChangeEvent.insert) {
              final message = change.newRecord;
              unawaited(announceIncoming(Map<String, dynamic>.from(message)));
            }
            refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_chats',
          callback: (_) {
            refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_receipts',
          callback: (_) {
            refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_reactions',
          callback: (_) {
            refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pulse_posts',
          callback: (_) {
            refresh();
          },
        )
        .subscribe();
    // Reconciliation also catches changes missed during network loss.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      refresh();
    });
  }

  Future<void> refresh() async {
    if (_disposed || busy || db.auth.currentUser == null) return;
    busy = true;
    final gen = _generation;
    try {
      final own = await db
          .from('pulse_profiles')
          .select()
          .eq('id', uid)
          .single();
      final access = await rpc('creator_access', {});
      final cs = await db
          .from('pulse_chats')
          .select('*,pulse_members(user_id,role)')
          .order('created_at', ascending: false)
          .limit(200);
      final requests = await db.from('pulse_chat_requests').select();
      final unreadData = await rpc('unread_counts', {});
      List<dynamic> summaryData = chatSummaries.values.toList();
      try {
        summaryData = await rpc('chat_summaries', {}) as List;
      } on PostgrestException catch (e) {
        if (!['PGRST202', '42883'].contains(e.code)) rethrow;
      }
      final ids = <String>{uid};
      for (final c in cs) {
        for (final m in c['pulse_members'] as List) {
          ids.add(m['user_id'] as String);
        }
      }
      final ps = await db
          .from('pulse_profiles')
          .select()
          .inFilter('id', ids.toList());
      final st = await db
          .from('pulse_statuses')
          .select()
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(100);
      final ch = await db
          .from('pulse_channels')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final fo = await db.from('pulse_followers').select().limit(10000);
      final po = await db
          .from('pulse_posts')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final bl = await db.from('pulse_blocks').select();
      List<Row> ms = [], rs = [], re = [], pref = [];
      if (activeChat != null) {
        ms = await db
            .from('pulse_messages')
            .select()
            .eq('chat_id', activeChat!)
            .order('created_at', ascending: false)
            .limit(200);
        final mids = ms.map((m) => m['id'] as String).toList();
        if (mids.isNotEmpty) {
          rs = await db
              .from('pulse_receipts')
              .select()
              .inFilter('message_id', mids);
          re = await db
              .from('pulse_reactions')
              .select()
              .inFilter('message_id', mids);
          pref = await db
              .from('pulse_message_preferences')
              .select()
              .inFilter('message_id', mids);
        }
      }
      if (gen != _generation) return;
      me = own;
      motionUntil = access['motion'] == true ? DateTime.utc(9999) : null;
      for (final p in ps) {
        profiles[p['id']] = p;
      }
      chats = cs;
      chatSummaries = {
        for (final row in summaryData as List)
          row['chat_id'] as String: Map<String, dynamic>.from(row as Map),
      };
      chatRequests = requests;
      unread = Map<String, dynamic>.from(
        unreadData as Map,
      ).map((k, v) => MapEntry(k, (v as num).toInt()));
      unawaited(PulseNotifications.instance.syncUnread(unread));
      statuses = st;
      channels = ch;
      followers = fo;
      posts = po;
      blocks = bl;
      messages
        ..clear()
        ..addAll(ms.reversed);
      receipts = rs;
      reactions = re;
      preferences = pref;
      error = null;
      await vault.write(
        key: _cacheKey,
        value: jsonEncode({
          'chats': chats,
          'summaries': chatSummaries.values.toList(),
          'profiles': profiles.values.toList(),
        }),
      );
      if (activeChat != null) {
        await vault.write(
          key: 'pulse.messages.$uid.$activeChat',
          value: jsonEncode(messages),
        );
      }
      await flush();
    } catch (_) {
      error =
          'Connection unavailable. Your queued messages will retry automatically.';
    } finally {
      busy = false;
      if (gen == _generation) notifyListeners();
    }
  }

  Future<void> openChat(String id) async {
    _generation++;
    activeChat = id;
    chatStyle = 'classic';
    unawaited(loadChatStyle(id));
    messages.clear();
    receipts = [];
    reactions = [];
    preferences = [];
    final saved = await vault.read(key: 'pulse.messages.$uid.$id');
    if (saved != null && activeChat == id)
      messages.addAll((jsonDecode(saved) as List).cast<Row>());
    notifyListeners();
    // Let an in-flight refresh finish; it cannot commit because its generation changed.
    while (busy) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await refresh();
  }

  Future<void> markRead([String? chat]) async {
    final target = chat ?? activeChat;
    final owner = db.auth.currentUser?.id;
    if (target == null || owner == null || error != null) return;
    await rpc('mark_read', {'p_chat': target});
    if (db.auth.currentUser?.id != owner || _disposed) return;
    unread[target] = 0;
    final stamp = DateTime.now().toUtc().toIso8601String();
    for (final m in messages.where(
      (m) => m['chat_id'] == target && m['sender_id'] != owner,
    )) {
      final existing = receipts
          .where((r) => r['message_id'] == m['id'] && r['user_id'] == owner)
          .firstOrNull;
      if (existing != null)
        existing['read_at'] = stamp;
      else
        receipts.add({
          'message_id': m['id'],
          'user_id': owner,
          'read_at': stamp,
          'delivered_at': stamp,
        });
    }
    await PulseNotifications.instance.clearChat(target);
    notifyListeners();
  }

  Future<void> fetchIncoming(String id) => announceIncoming({'id': id});

  Future<void> announceIncoming(Row hint) async {
    final owner = db.auth.currentUser?.id;
    final id = hint['id'] as String?;
    if (_disposed || owner == null || id == null || !_announced.add(id)) return;
    if (_announced.length > 500) _announced.remove(_announced.first);
    try {
      final preview = await rpc('unread_preview', {'p_message': id});
      if (preview == null || _disposed || db.auth.currentUser?.id != owner)
        return;
      final message = Map<String, dynamic>.from(preview['message']);
      final chat = message['chat_id'] as String;
      final count = (preview['unread_count'] as num?)?.toInt() ?? 0;
      if (count == 0) return;
      if (isChatVisible?.call(chat) == true) {
        await refresh();
        return;
      }
      unread[chat] = count;
      incoming = {...message, 'unread_count': count};
      incomingSerial++;
      notifyListeners();
      await PulseNotifications.instance.message(incoming!);
    } catch (_) {
      /* Skip unverified/replayed notification hints; sync continues. */
    }
  }

  Future<void> loadChatStyle(String chat) async {
    final owner = db.auth.currentUser?.id;
    try {
      final result = await rpc('user_tools', {
        'p_action': 'style_get',
        'p_chat': chat,
      });
      if (!_disposed &&
          activeChat == chat &&
          db.auth.currentUser?.id == owner) {
        chatStyle = result['style'] as String;
        notifyListeners();
      }
    } catch (_) {
      /* Classic is the safe fallback while offline. */
    }
  }

  Future<dynamic> rpc(String name, Row params) =>
      db.rpc('pulse_$name', params: params);
  Future<void> send(
    String body, {
    String? reply,
    String? attachment,
    String? chatId,
    String? mediaKind,
    String? mediaMime,
    int? duration,
    List<double>? waveform,
  }) async {
    if ((chatId ?? activeChat) == null ||
        (body.trim().isEmpty && attachment == null))
      return;
    if (!canReply(chatId ?? activeChat))
      throw StateError('Accept the message request before replying.');
    final row = <String, dynamic>{
      'id': const Uuid().v4(),
      'chat_id': chatId ?? activeChat,
      'sender_id': uid,
      'body': body.trim(),
      'reply_to': reply,
      'attachment_path': attachment,
      'media_kind': mediaKind,
      'media_mime': mediaMime,
      'duration_ms': duration,
      'waveform': waveform,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'pending': true,
    };
    pending.add(row);
    await vault.write(key: _queueKey, value: jsonEncode(pending));
    notifyListeners();
    await flush();
    await refresh();
  }

  Future<void> flush() async {
    if (syncing || db.auth.currentUser == null) return;
    final owner = uid, generation = _generation;
    final queueKey = 'pulse.outbox.$owner';
    syncing = true;
    try {
      for (final p in List<Row>.from(
        pending.where((p) => p['failure'] == null),
      )) {
        if (generation != _generation || db.auth.currentUser?.id != owner)
          break;
        try {
          await rpc(
            p['media_kind'] == null ? 'send_message' : 'send_media_message',
            {
              'p_id': p['id'],
              'p_chat': p['chat_id'],
              'p_body': p['body'],
              'p_reply': p['reply_to'],
              'p_attachment': p['attachment_path'],
              if (p['media_kind'] != null) ...{
                'p_kind': p['media_kind'],
                'p_mime': p['media_mime'],
                'p_duration': p['duration_ms'],
                'p_waveform': p['waveform'],
              },
            },
          );
          if (generation != _generation || db.auth.currentUser?.id != owner)
            break;
          pending.remove(p);
          await vault.write(key: queueKey, value: jsonEncode(pending));
        } on PostgrestException catch (e) {
          // Authorization/validation failures need the user's attention, not endless retries.
          if (generation != _generation || db.auth.currentUser?.id != owner)
            break;
          p['failure'] = e.message;
          await vault.write(key: queueKey, value: jsonEncode(pending));
        } catch (_) {
          break;
        }
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> discardPending(String id) async {
    pending.removeWhere((p) => p['id'] == id);
    await vault.write(key: _queueKey, value: jsonEncode(pending));
    notifyListeners();
  }

  List<Row> get visibleMessages {
    final hidden = preferences
        .where((p) => p['hidden'] == true)
        .map((p) => p['message_id'])
        .toSet();
    final result = messages.where((m) => !hidden.contains(m['id'])).toList();
    final ids = result.map((m) => m['id']).toSet();
    result.addAll(
      pending.where(
        (p) => p['chat_id'] == activeChat && !ids.contains(p['id']),
      ),
    );
    return result;
  }

  String chatName(Row chat) {
    if (chat['kind'] == 'group') return chat['name'];
    final members = (chat['pulse_members'] as List).where(
      (m) => m['user_id'] != uid,
    );
    if (members.isEmpty) return 'Pulse chat';
    return profiles[members.first['user_id']]?['display_name'] ?? 'Pulse user';
  }

  final _avatarEntitlements =
      <String, ({DateTime cachedAt, DateTime? expiry})>{};
  Future<DateTime?> avatarMotionExpiry(String? path) async {
    if (path == null ||
        (!path.toLowerCase().endsWith('.gif') && !isProfileVideo(path)))
      return null;
    final owner = path.split('/').first;
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(owner)) return null;
    final cached = _avatarEntitlements[owner];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) <
            const Duration(seconds: 45))
      return cached.expiry;
    final value = await rpc('profile_features', {'p_user': owner});
    final expiry = value is Map
        ? DateTime.tryParse(value['motion_until']?.toString() ?? '')
        : null;
    if (_avatarEntitlements.length >= 128)
      _avatarEntitlements.remove(_avatarEntitlements.keys.first);
    _avatarEntitlements[owner] = (cachedAt: DateTime.now(), expiry: expiry);
    return expiry;
  }

  Future<String?> avatar(String? path) async => path == null
      ? null
      : db.storage.from('pulse-avatars').createSignedUrl(path, 3600);
  Future<String> uploadProfileVideo(File video, File poster) async {
    if (await video.length() > 15728640 || await poster.length() > 15728640)
      throw const FormatException('Profile media must be 15 MB or smaller');
    final path = '$uid/${const Uuid().v4()}-motion.mp4';
    final preview = profilePosterPath(path);
    final bucket = db.storage.from('pulse-avatars');
    try {
      await bucket.upload(
        preview,
        poster,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
      await bucket.upload(
        path,
        video,
        fileOptions: const FileOptions(contentType: 'video/mp4'),
      );
      return path;
    } catch (_) {
      try {
        await bucket.remove([preview, path]);
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> upload(
    File file,
    String filename, {
    bool avatar = false,
    String? contentType,
    String? chatId,
  }) async {
    if (await file.length() > (avatar ? 15728640 : 10485760))
      throw Exception(
        avatar
            ? 'Avatar must be 15 MB or smaller'
            : 'File must be under 10 MB in this beta',
      );
    if (!avatar && (chatId ?? activeChat) == null)
      throw Exception('Choose a chat first');
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = avatar
        ? '$uid/${const Uuid().v4()}-$safe'
        : '${chatId ?? activeChat}/$uid/${const Uuid().v4()}-$safe';
    await db.storage
        .from(avatar ? 'pulse-avatars' : 'pulse-media')
        .upload(path, file, fileOptions: FileOptions(contentType: contentType));
    return path;
  }

  Future<void> signOut({bool all = false}) async {
    final owner = uid;
    // Do not discard the outbox or stop reconciliation before revocation succeeds.
    final keys = await vault.readAll();
    await PulsePush.instance.disable(all: all);
    await db.auth.signOut(
      scope: all ? SignOutScope.global : SignOutScope.local,
    );
    _generation++;
    _timer?.cancel();
    await PulseNotifications.instance.clearAll();
    for (final key in keys.keys.where(
      (k) => k.startsWith('pulse.') && k.contains(owner),
    )) {
      await vault.delete(key: key);
    }
  }

  @override
  void dispose() {
    presence.dispose();
    _disposed = true;
    PulsePush.instance.onMessage = null;
    _generation++;
    _timer?.cancel();
    if (_realtime != null) db.removeChannel(_realtime!);
    super.dispose();
  }
}
