import 'dart:async';
import 'package:flutter/widgets.dart';
import 'repository.dart';
import 'activity_alerts.dart';
import 'notifications.dart';

class PulseActivityController extends ChangeNotifier
    with WidgetsBindingObserver {
  PulseActivityController(this.repo) : owner = repo.uid;
  final PulseRepository repo;
  final String owner;
  int unread = 0, requestSerial = 0, appliedSerial = 0;
  bool disposed = false, refreshing = false, started = false;
  Timer? timer;
  final alerts = PulseActivityAlerts();
  int viewing = 0;
  Map<String, bool> preferences = {
    'mentions': true,
    'follows': true,
    'likes': true,
    'comments': true,
    'following': true,
  };
  bool get active => !disposed && repo.db.auth.currentUser?.id == owner;
  void start() {
    if (started) return;
    started = true;
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<Map<String, dynamic>> page({
    Map<String, dynamic>? cursor,
    int limit = 30,
  }) async {
    if (!active) throw StateError('Account changed');
    final ticket = ++requestSerial;
    final result = await repo
        .rpc('activity', {
          'p_before': cursor?['created_at'],
          'p_cursor': cursor?['id'],
          'p_limit': limit,
        })
        .timeout(const Duration(seconds: 15));
    if (!active) throw StateError('Account changed');
    final data = Map<String, dynamic>.from(result as Map);
    if (ticket < appliedSerial) return data;
    appliedSerial = ticket;
    unread = (data['unread'] as num?)?.toInt() ?? 0;
    final settings = data['preferences'] as Map?;
    if (settings != null)
      preferences = {for (final k in preferences.keys) k: settings[k] == true};
    notifyListeners();
    return data;
  }

  Future<void> refresh() async {
    if (!active || refreshing) return;
    refreshing = true;
    try {
      final data = await page(limit: 30);
      if (!active) return;
      final items = [
        for (final row in data['items'] as List? ?? [])
          Map<String, dynamic>.from(row as Map),
      ];
      final updates = alerts.collect(
        items,
        viewing: viewing > 0,
        asOf: data['as_of'] as String?,
      );
      for (final entry in updates.entries) {
        if (!active) return;
        await PulseNotifications.instance.activity(
          entry.key,
          entry.value,
          owner,
        );
      }
    } catch (_) {
      /* Keep the last confirmed badge while offline. */
    } finally {
      refreshing = false;
    }
  }

  Future<void> read({String? id, String? until}) async {
    if (!active) return;
    await repo
        .rpc('activity_read', {'p_event': id, 'p_until': until})
        .timeout(const Duration(seconds: 15));
    await page(limit: 1);
  }

  Future<void> savePreferences(Map<String, bool> settings) async {
    if (!active) throw StateError('Account changed');
    await repo
        .rpc('activity_preferences', {
          for (final e in settings.entries) 'p_${e.key}': e.value,
        })
        .timeout(const Duration(seconds: 15));
    await page(limit: 1);
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    if (started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
