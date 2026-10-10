import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'notifications.dart';
import 'push.dart';

typedef Row = Map<String, dynamic>;

class PulseRepository extends ChangeNotifier {
  PulseRepository(this.db);
  final SupabaseClient db;
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
      for (final p in (c['profiles'] as List).cast<Row>()) {
        profiles[p['id']] = p;
      }
      me = profiles[uid];
    }
    if (_disposed || db.auth.currentUser == null) return;
    await refresh();
    if (_disposed || db.auth.currentUser == null) return;
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
              if (message['sender_id'] != uid) {
                unawaited(PulseNotifications.instance.message(message));
              }
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
      final cs = await db
          .from('pulse_chats')
          .select('*,pulse_members(user_id,role)')
          .order('created_at', ascending: false)
          .limit(200);
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
      for (final p in ps) {
        profiles[p['id']] = p;
      }
      chats = cs;
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
      error = 'Connection unavailable. Your queued messages will retry automatically.';
    } finally {
      busy = false;
      if (gen == _generation) notifyListeners();
    }
  }

  Future<void> openChat(String id) async {
    _generation++;
    activeChat = id;
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

  Future<void> markRead() async {
    if (activeChat != null && error == null)
      await rpc('mark_read', {'p_chat': activeChat});
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
    syncing = true;
    try {
      for (final p in List<Row>.from(
        pending.where((p) => p['failure'] == null),
      )) {
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
          pending.remove(p);
          await vault.write(key: _queueKey, value: jsonEncode(pending));
        } on PostgrestException catch (e) {
          // Authorization/validation failures need the user's attention, not endless retries.
          p['failure'] = e.message;
          await vault.write(key: _queueKey, value: jsonEncode(pending));
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

  Future<String?> avatar(String? path) async => path == null
      ? null
      : db.storage.from('pulse-avatars').createSignedUrl(path, 3600);
  Future<String> upload(
    File file,
    String filename, {
    bool avatar = false,
    String? contentType,
    String? chatId,
  }) async {
    if (await file.length() > (avatar ? 2097152 : 10485760))
      throw Exception(
        avatar
            ? 'Avatar must be under 2 MB'
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
    await PulsePush.instance.disable(all: all);
    _generation++;
    _timer?.cancel();
    if (_realtime != null) await db.removeChannel(_realtime!);
    final keys = await vault.readAll();
    for (final key in keys.keys.where(
      (k) => k.startsWith('pulse.') && k.contains(uid),
    )) {
      await vault.delete(key: key);
    }
    await db.auth.signOut(
      scope: all ? SignOutScope.global : SignOutScope.local,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_realtime != null) db.removeChannel(_realtime!);
    super.dispose();
  }
}
