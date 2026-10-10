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
  bool enabled = false, _ready = false;
  Future<void> initialize() async {
    try {
      enabled = await _vault.read(key: 'pulse.notifications.enabled') == 'true';
      if (!Platform.isAndroid && !Platform.isWindows) return;
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_pulse_notification'),
          windows: WindowsInitializationSettings(
            appName: 'Pulse Messenger',
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

  Future<bool> _show(int id, String title, String body) async {
    if (!enabled || !_ready) return false;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'pulse_messages',
            'Pulse messages',
            channelDescription: 'New private and group messages',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            icon: 'ic_pulse_notification',
          ),
          windows: WindowsNotificationDetails(),
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
    // Do not expose message text or attachments on the lock screen.
    await _show(
      id.hashCode & 0x7fffffff,
      'Pulse Messenger',
      'You have a new message.',
    );
  }

  Future<bool> incomingCall(String id, bool video) => _show(
    id.hashCode & 0x7fffffff,
    'Pulse Messenger',
    video
        ? 'Incoming video call. Open Pulse to answer.'
        : 'Incoming voice call. Open Pulse to answer.',
  );

  Future<bool> test() =>
      _show(1, 'Pulse Messenger', 'Your Pulse notifications are enabled.');
}
