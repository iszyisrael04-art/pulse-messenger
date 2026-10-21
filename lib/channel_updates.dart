import 'notifications.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';

class PulseChannelUpdates extends ChangeNotifier with WidgetsBindingObserver {
  PulseChannelUpdates(this.repo) : owner = repo.uid;
  final PulseRepository repo;
  final String owner;
  Map<String, int> counts = {};
  Map<String, dynamic>? latest;
  int serial = 0, total = 0, revision = 0;
  String? activeChannel;
  bool Function()? activeChannelVisible;
  bool viewing(String id) =>
      activeChannel == id && (activeChannelVisible?.call() ?? false);
  bool disposed = false, busy = false;
  final seen = <String>{};
  Timer? timer;
  RealtimeChannel? realtime;
  bool get valid => !disposed && repo.db.auth.currentUser?.id == owner;
  void start() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
    realtime = repo.db
        .channel('channel-updates:$owner')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pulse_posts',
          callback: (_) => refresh(),
        )
        .subscribe();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    if (!valid || busy) return;
    busy = true;
    final ticket = revision;
    try {
      final data = await repo
          .rpc('channel_updates', {'p_action': 'list'})
          .timeout(const Duration(seconds: 12));
      if (!valid || ticket != revision) return;
      final previousChannels = counts.keys.toSet();
      counts = {
        for (final r in data['counts'] as List)
          r['channel_id'] as String: (r['unread'] as num).toInt(),
      };
      total = (data['total'] as num).toInt();
      for (final channel in previousChannels.difference(counts.keys.toSet())) {
        unawaited(PulseNotifications.instance.clearChannel(channel));
      }
      final pendingAlerts = <String, Map>{};
      final items = (data['items'] as List).cast<Map>();
      for (final row in items.reversed) {
        final id = row['id'] as String;
        if (!seen.add(id)) continue;
        if (seen.length > 500) seen.remove(seen.first);
        if (viewing(row['channel_id'] as String)) continue;
        latest = Map<String, dynamic>.from(row);
        serial++;
        pendingAlerts[row['channel_id'] as String] = row;
      }
      for (final row in pendingAlerts.values) {
        if (valid)
          unawaited(
            PulseNotifications.instance.channelUpdate(
              row['channel_id'],
              row['id'],
              counts[row['channel_id']] ?? 0,
            ),
          );
      }
      notifyListeners();
    } catch (_) {
      /* Keep offline state and retry without alert spam. */
    } finally {
      busy = false;
    }
  }

  Future<void> read(String channel, {String? post}) async {
    if (!valid) return;
    revision++;
    await repo.rpc('channel_updates', {
      'p_action': 'read',
      'p_channel': channel,
      'p_post': post,
    });
    if (!valid) return;
    unawaited(PulseNotifications.instance.clearChannel(channel));
    counts.remove(channel);
    total = counts.values.fold(0, (a, b) => a + b);
    notifyListeners();
    await refresh();
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (realtime != null) unawaited(repo.db.removeChannel(realtime!));
    super.dispose();
  }
}
