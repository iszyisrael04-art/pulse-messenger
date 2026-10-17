import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'notifications.dart';

/// Optional Android FCM. Public Firebase app options are compile-time configuration.
/// Service account credentials exist only in the server dispatcher.
class PulsePush {
  PulsePush._();
  static final instance = PulsePush._();
  static const vault = FlutterSecureStorage();
  bool configured = false;
  void Function(String)? onMessage;
  String? status;
  StreamSubscription<String>? _refresh;
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if ([apiKey, appId, sender, project].any((s) => s.isEmpty)) {
      status = 'Background push needs Firebase configuration.';
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
        ),
      );
      // Start opted out. FCM auto-init is disabled until user enables notifications.
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      configured = true;
      FirebaseMessaging.onMessage.listen((message) {
        final id = message.data['message_id'];
        if (id != null) onMessage?.call(id);
      });
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (PulseNotifications.instance.enabled) unawaited(_register(token));
      });
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.session != null && PulseNotifications.instance.enabled)
          unawaited(enable());
      });
      if (PulseNotifications.instance.enabled) await enable();
    } catch (_) {
      status =
          'Firebase could not initialize. Local alerts are still available.';
    }
  }

  Future<String?> _device() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final key = 'pulse.push.device.${user.id}';
    var id = await vault.read(key: key);
    if (id == null) {
      id = const Uuid().v4();
      await vault.write(key: key, value: id);
    }
    return id;
  }

  Future<void> _register(String token) async {
    try {
      final device = await _device();
      if (device == null) return;
      await Supabase.instance.client.rpc(
        'pulse_push_register',
        params: {'p_device': device, 'p_token': token},
      );
      status =
          'Android background push registered. Server dispatcher must also be configured.';
    } catch (_) {
      status = 'Push registration failed. Local alerts remain available.';
    }
  }

  Future<void> enable() async {
    if (!configured) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (_) {
      status = 'Push registration unavailable. Check Google Play services.';
    }
  }

  Future<void> disable({bool all = false}) async {
    if (!configured) return;
    final device = await _device();
    if (device != null) {
      // Fail before logging out if the server could not unregister this device.
      await Supabase.instance.client.rpc(
        'pulse_push_disable',
        params: {'p_device': device, 'p_all': all},
      );
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken();
  }
}
