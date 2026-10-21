import 'dart:io';

import 'push.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local operating-system alerts. This does not keep Android alive or provide push.
class PulseNotifications {
  PulseNotifications._();
  static final instance = PulseNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _vault = FlutterSecureStorage();
  final _seen = <String>{};
  final _chatCounts = <String, int>{};
  Future<void> clearChat(String chat) async {
    _chatCounts.remove(chat);
    try {
      await _plugin.cancel(chat.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  Future<void> syncUnread(Map<String, int> counts) async {
    for (final chat in _chatCounts.keys.toList()) {
      final next = counts[chat] ?? 0;
      final previous = _chatCounts[chat] ?? 0;
      if (next == 0) {
        await clearChat(chat);
      } else {
        _chatCounts[chat] = next;
        if (next < previous)
          await _show(
            chat.hashCode & 0x7fffffff,
            'Pulse',
            '$next new message${next == 1 ? '' : 's'}',
            number: next,
          );
      }
    }
  }

  Future<void> clearAll() async {
    _seen.clear();
    _chatCounts.clear();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  bool enabled = false, _ready = false;
  Future<void> initialize() async {
    try {
      enabled = await _vault.read(key: 'pulse.notifications.enabled') == 'true';
      if (!Platform.isAndroid && !Platform.isWindows) return;
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_pulse_notification'),
          windows: WindowsInitializationSettings(
            appName: 'Pulse',
            appUserModelId: 'com.pulsemessenger.pulse',
            guid: '30f995ac-7aee-4cb1-8cc4-5f046026f024',
          ),
        ),
      );
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'pulse_messages',
                'Pulse messages',
                description: 'New private and group messages',
                importance: Importance.high,
              ),
            );
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value && Platform.isAndroid) {
      final allowed = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      value = allowed == true;
    }
    if (value) {
      await PulsePush.instance.enable();
    } else {
      await PulsePush.instance.disable();
    }
    enabled = value;
    await _vault.write(key: 'pulse.notifications.enabled', value: '$value');
  }

  Future<bool> _show(int id, String title, String body, {int? number}) async {
    if (!enabled || !_ready) return false;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'pulse_messages',
            'Pulse messages',
            channelDescription: 'New private and group messages',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            icon: 'ic_pulse_notification',
            number: number,
            groupKey: 'pulse_messages',
            onlyAlertOnce: true,
          ),
          windows: const WindowsNotificationDetails(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> message(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || !_seen.add(id)) return;
    if (_seen.length > 500) _seen.remove(_seen.first);
    final chat = message['chat_id'] as String?;
    final count = (message['unread_count'] as num?)?.toInt() ?? 0;
    if (chat == null || count <= 0) return;
    _chatCounts[chat] = count;
    await _show(
      chat.hashCode & 0x7fffffff,
      'Pulse',
      '$count new message${count == 1 ? '' : 's'}',
      number: count,
    );
  }

  Future<void> clearChannel(String channel) async {
    try {
      await _plugin.cancel(('channel:$channel').hashCode & 0x7fffffff);
    } catch (_) {}
  }

  Future<void> channelUpdate(String channel, String post, int count) async {
    if (count <= 0 || !_seen.add('channel:$post')) return;
    if (_seen.length > 500) _seen.remove(_seen.first);
    await _show(
      ('channel:$channel').hashCode & 0x7fffffff,
      'Pulse channel update',
      '$count unread announcement${count == 1 ? '' : 's'}',
      number: count,
    );
  }

  Future<bool> incomingCall(String id, bool video) => _show(
    id.hashCode & 0x7fffffff,
    'Pulse',
    video
        ? 'Incoming video call. Open Pulse to answer.'
        : 'Incoming voice call. Open Pulse to answer.',
  );

  Future<bool> test() =>
      _show(1, 'Pulse', 'Your Pulse notifications are enabled.');
}
