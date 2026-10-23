import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'presence_rules.dart';

class PulsePresence extends ChangeNotifier with WidgetsBindingObserver {
  PulsePresence({required this.rpc, required this.owner, required this.peers});
  final Future<dynamic> Function(String, Map<String, dynamic>) rpc;
  final String Function() owner;
  final Iterable<String> Function() peers;
  final device = const Uuid().v4();
  final statuses = <String, PulseActiveStatus>{};
  final watched = <String, int>{};
  Timer? timer;
  bool? sharing;
  bool started = false,
      foreground = true,
      syncing = false,
      queued = false,
      closed = false;
  int sequence = 0, generation = 0, privacyGeneration = 0;
  void start() {
    if (started || closed) return;
    started = true;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (foreground) refresh();
    });
    unawaited(refresh());
  }

  void watch(String id) {
    watched[id] = (watched[id] ?? 0) + 1;
    if (started && !statuses.containsKey(id)) scheduleMicrotask(refresh);
  }

  void unwatch(String id) {
    final count = watched[id] ?? 0;
    if (count <= 1)
      watched.remove(id);
    else
      watched[id] = count - 1;
  }

  Future<void> refresh() async {
    queued = true;
    if (!started || syncing || closed) return;
    syncing = true;
    try {
      while (queued && !closed) {
        queued = false;
        final own = generation;
        final privacy = privacyGeneration;
        final active = foreground;
        try {
          final result = await rpc('presence_tick', {
            'p_device': device,
            'p_sequence': ++sequence,
            'p_active': active,
          }).timeout(const Duration(seconds: 8));
          if (closed) return;
          if (privacy == privacyGeneration) sharing = result['sharing'] == true;
          if (active && own == generation) {
            final ids = <String>{
              owner(),
              ...watched.keys,
              ...peers(),
            }.take(200).toList();
            final data = await rpc('presence_info', {
              'p_users': ids,
            }).timeout(const Duration(seconds: 8));
            if (closed || own != generation) continue;
            final now = DateTime.now();
            statuses.clear();
            for (final row in data as List) {
              statuses[row['user_id'] as String] = PulseActiveStatus.fromServer(
                row as Map,
                now,
              );
            }
          }
          if (!closed) notifyListeners();
        } catch (_) {
          if (!closed) {
            statuses.clear();
            notifyListeners();
          }
        }
      }
    } finally {
      syncing = false;
    }
  }

  Future<void> setSharing(bool value) async {
    final own = ++privacyGeneration;
    await rpc('presence_sharing', {
      'p_enabled': value,
    }).timeout(const Duration(seconds: 10));
    if (closed) return;
    if (own == privacyGeneration) sharing = value;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    generation++;
    if (!foreground) statuses.clear();
    if (!closed) notifyListeners();
    unawaited(refresh());
  }

  @override
  void dispose() {
    closed = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (started) {
      unawaited(
        Future<dynamic>.sync(
              () => rpc('presence_tick', {
                'p_device': device,
                'p_sequence': ++sequence,
                'p_active': false,
              }),
            )
            .timeout(const Duration(seconds: 5))
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    statuses.clear();
    watched.clear();
    super.dispose();
  }
}
