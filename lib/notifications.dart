import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push.dart';
import 'activity_alerts.dart';

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
    _pendingActivityTap = false;
    _pendingCallTap = null;
    _seen.clear();
    _chatCounts.clear();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  void Function(String)? _callTap;
  String? _pendingCallTap;
  void setCallTap(void Function(String)? handler) {
    _callTap = handler;
    final id = _pendingCallTap;
    if (handler != null && id != null) {
      _pendingCallTap = null;
      handler(id);
    }
  }

  Future<void> clearCall(String id) async {
    try {
      await _plugin.cancel(id.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  void callTapped(String id) {
    final actual = id.startsWith('answer:')
        ? id.substring(7)
        : id.startsWith('decline:')
        ? id.substring(8)
        : id;
    unawaited(clearCall(actual));
    if (_callTap == null) {
      _pendingCallTap = id;
    } else {
      _callTap!(id);
    }
  }

  void Function()? _activityTap;
  bool _pendingActivityTap = false;
  void setActivityTap(void Function()? handler) {
    _activityTap = handler;
    if (handler != null && _pendingActivityTap) {
      _pendingActivityTap = false;
      handler();
    }
  }

  void activityTapped() {
    final handler = _activityTap;
    if (handler == null) {
      _pendingActivityTap = true;
    } else {
      handler();
    }
  }

  Future<void> activity(String kind, int count, String owner) async {
    if (count <= 0) return;
    await _show(
      ('activity:$owner:$kind').hashCode & 0x7fffffff,
      'Pulse activity',
      pulseActivityAlertBody(kind, count),
      number: count,
      payload: 'pulse:activity',
      activityAlert: true,
    );
  }

  bool enabled = false, _ready = false;
  Future<void> initialize() async {
    try {
      enabled = await _vault.read(key: 'pulse.notifications.enabled') == 'true';
      if (!Platform.isAndroid && !Platform.isWindows && !Platform.isIOS) return;
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_pulse_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'Pulse',
            appUserModelId: 'com.pulsemessenger.pulse',
            guid: '30f995ac-7aee-4cb1-8cc4-5f046026f024',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == 'pulse:activity') activityTapped();
          if (response.payload?.startsWith('pulse:call:') == true)
            callTapped(
              '${(response.actionId ?? '').isEmpty ? '' : '${response.actionId}:'}${response.payload!.substring(11)}',
            );
        },
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
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true &&
            launch?.notificationResponse?.payload == 'pulse:activity')
          _pendingActivityTap = true;
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true &&
            payload?.startsWith('pulse:call:') == true)
          _pendingCallTap =
              '${(launch?.notificationResponse?.actionId ?? '').isNotEmpty ? '${launch!.notificationResponse!.actionId}:' : ''}${payload!.substring(11)}';
      } catch (_) {
        /* Some Windows hosts do not supply launch metadata. */
      }
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
      if (value) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestFullScreenIntentPermission();
      }
    }
    if (value && Platform.isIOS) {
      final allowed = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
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

  Future<bool> _show(
    int id,
    String title,
    String body, {
    int? number,
    String? payload,
    bool activityAlert = false,
    bool callAlert = false,
  }) async {
    if (!enabled || !_ready) return false;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            callAlert
                ? 'pulse_calls_v2'
                : activityAlert
                ? 'pulse_activity'
                : 'pulse_messages',
            callAlert
                ? 'Pulse calls'
                : activityAlert
                ? 'Pulse activity'
                : 'Pulse messages',
            channelDescription: activityAlert
                ? 'Likes, comments, follows and mentions'
                : 'New private and group messages',
            category: callAlert ? AndroidNotificationCategory.call : null,
            fullScreenIntent: callAlert,
            ongoing: callAlert,
            autoCancel: !callAlert,
            timeoutAfter: callAlert ? 45000 : null,
            sound: callAlert
                ? const RawResourceAndroidNotificationSound('pulse_ringtone')
                : null,
            actions: callAlert
                ? const [
                    AndroidNotificationAction(
                      'answer',
                      'Answer',
                      showsUserInterface: true,
                    ),
                    AndroidNotificationAction(
                      'decline',
                      'Decline',
                      showsUserInterface: true,
                    ),
                  ]
                : null,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            icon: 'ic_pulse_notification',
            number: number,
            groupKey: callAlert
                ? 'pulse_calls_v2'
                : activityAlert
                ? 'pulse_activity'
                : 'pulse_messages',
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            threadIdentifier: callAlert ? 'pulse_calls' : 'pulse_messages',
          ),
          windows: const WindowsNotificationDetails(),
        ),
        payload: payload,
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

  String _channelMuteKey(String channel) =>
      'channel-muted:${Supabase.instance.client.auth.currentUser?.id}:$channel';
  Future<bool> channelMuted(String channel) async {
    try {
      return await _vault.read(key: _channelMuteKey(channel)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> muteChannel(String channel, bool muted) async {
    await _vault.write(key: _channelMuteKey(channel), value: '$muted');
    if (muted) await clearChannel(channel);
  }

  Future<void> channelUpdate(String channel, String post, int count) async {
    if (await channelMuted(channel)) return;
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
    video ? 'Incoming video call' : 'Incoming voice call',
    callAlert: true,
    payload: 'pulse:call:$id',
  );

  Future<bool> test() =>
      _show(1, 'Pulse', 'Your Pulse notifications are enabled.');
}
